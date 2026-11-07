import Foundation
import CoreLocation
import Supabase

/// Owns all game state: the Supabase session, the current game, realtime
/// subscription, and the role-specific behaviour (runner reveals, vehicle
/// detection, hunter alerts).
@MainActor
final class GameService: ObservableObject {
    let client = SupabaseClient(supabaseURL: Config.supabaseURL, supabaseKey: Config.supabaseAnonKey)
    let location = LocationManager()
    let motion = MotionDetector()

    @Published private(set) var userId: UUID?
    @Published private(set) var game: Game?
    @Published private(set) var players: [Player] = []
    /// Newest first.
    @Published private(set) var pings: [Ping] = []
    @Published private(set) var lastVehiclePingAt: Date?
    @Published private(set) var lastRevealAt: Date?
    @Published var pendingJoinCode: String?
    @Published var errorMessage: String?
    @Published private(set) var isBusy = false

    private var channel: RealtimeChannelV2?
    private var listeners: [Task<Void, Never>] = []
    private var ticker: Timer?
    private var seenPingIds = Set<Int>()
    private var lastPublishedSlot = -1
    private var activeRole: Role?
    private var isFinishing = false

    private let savedGameKey = "manhunt.currentGameId"

    init() {
        location.onUpdate = { [weak self] in self?.handleLocation($0) }
        motion.onVehicleDetected = { [weak self] in self?.handleVehicleDetected() }
    }

    // MARK: - Derived state

    var me: Player? { players.first { $0.userId == userId } }
    var isHost: Bool { userId != nil && game?.hostId == userId }
    var runners: [Player] { players.filter { $0.role == .runner } }
    var hunters: [Player] { players.filter { $0.role == .hunter } }
    var runnersRemaining: Int { runners.filter { !$0.isCaught }.count }

    var inviteURL: URL? {
        guard let code = game?.code else { return nil }
        return URL(string: "\(Config.urlScheme)://join?code=\(code)")
    }

    func latestPing(for runnerId: UUID) -> Ping? {
        pings.first { $0.runnerId == runnerId }
    }

    func name(of userId: UUID) -> String {
        players.first { $0.userId == userId }?.name ?? "A runner"
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        await NotificationManager.shared.requestAuthorization()
        do {
            try await ensureSignedIn()
        } catch {
            errorMessage = "Couldn't sign in: \(Self.describe(error))"
            return
        }
        // Resume a game after the app was killed.
        if game == nil,
           let saved = UserDefaults.standard.string(forKey: savedGameKey),
           let id = UUID(uuidString: saved) {
            do {
                let g: Game = try await client.from("games").select()
                    .eq("id", value: id.uuidString).single().execute().value
                await enter(g)
            } catch {
                UserDefaults.standard.removeObject(forKey: savedGameKey)
            }
        }
    }

    func handle(url: URL) {
        guard url.scheme == Config.urlScheme, url.host == "join",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        else { return }
        pendingJoinCode = code.uppercased()
    }

    @discardableResult
    private func ensureSignedIn() async throws -> UUID {
        if let userId { return userId }
        let session: Session
        if let existing = try? await client.auth.session {
            session = existing
        } else {
            session = try await client.auth.signInAnonymously()
        }
        userId = session.user.id
        return session.user.id
    }

    // MARK: - Actions

    func createGame(name: String, durationMinutes: Int, headStartMinutes: Int) async {
        await perform {
            try await self.ensureSignedIn()
            let params = CreateGameParams(name: name, duration: durationMinutes, headStart: headStartMinutes)
            let g: Game = try await self.client.rpc("create_game", params: params).execute().value
            await self.enter(g)
        }
    }

    func joinGame(code: String, name: String) async {
        await perform {
            try await self.ensureSignedIn()
            let params = JoinGameParams(code: code, name: name)
            let g: Game = try await self.client.rpc("join_game", params: params).execute().value
            await self.enter(g)
        }
    }

    /// Host only. The server shuffles everyone into runners and hunters.
    func startGame() async {
        guard let g = game else { return }
        await perform {
            let started: Game = try await self.client.rpc("start_game", params: GameIdParams(gameId: g.id)).execute().value
            self.game = started
            await self.refreshPlayers()
            self.updateRoleServices()
        }
    }

    /// Runner gives themselves up, or a hunter tags a runner.
    func markCaught(_ runnerId: UUID) async {
        guard let g = game else { return }
        await perform {
            try await self.client.rpc("mark_caught", params: MarkCaughtParams(gameId: g.id, runnerId: runnerId)).execute()
            await self.refreshPlayers()
            await self.refreshGame()
        }
    }

    func leaveGame() async {
        if let g = game, g.status == .lobby {
            try? await client.rpc("leave_game", params: GameIdParams(gameId: g.id)).execute()
        }
        await teardown()
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do { try await work() } catch { errorMessage = Self.describe(error) }
    }

    // MARK: - Entering / leaving a game

    private func enter(_ g: Game) async {
        game = g
        UserDefaults.standard.set(g.id.uuidString, forKey: savedGameKey)
        lastPublishedSlot = UserDefaults.standard.object(forKey: slotKey(g.id)) as? Int ?? -1
        seenPingIds = []
        await refreshPlayers()
        await refreshPings(notify: false)
        await subscribe(to: g.id)
        updateRoleServices()
        startTicker()
    }

    private func teardown() async {
        listeners.forEach { $0.cancel() }
        listeners = []
        if let channel { await client.removeChannel(channel) }
        channel = nil
        ticker?.invalidate()
        ticker = nil
        stopRoleServices()
        if let g = game { UserDefaults.standard.removeObject(forKey: slotKey(g.id)) }
        UserDefaults.standard.removeObject(forKey: savedGameKey)
        game = nil
        players = []
        pings = []
        seenPingIds = []
        lastVehiclePingAt = nil
        lastRevealAt = nil
        lastPublishedSlot = -1
    }

    private func slotKey(_ id: UUID) -> String { "manhunt.slot.\(id.uuidString)" }

    // MARK: - Realtime

    private func subscribe(to gameId: UUID) async {
        listeners.forEach { $0.cancel() }
        if let channel { await client.removeChannel(channel) }

        let id = gameId.uuidString
        let channel = client.channel("game-\(id)")
        let gameChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "games", filter: "id=eq.\(id)")
        let playerChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "players", filter: "game_id=eq.\(id)")
        let pingInserts = channel.postgresChange(InsertAction.self, schema: "public", table: "pings", filter: "game_id=eq.\(id)")
        await channel.subscribe()
        self.channel = channel

        listeners = [
            Task { [weak self] in
                for await _ in gameChanges { await self?.refreshGame() }
            },
            Task { [weak self] in
                for await _ in playerChanges { await self?.refreshPlayers() }
            },
            Task { [weak self] in
                for await _ in pingInserts { await self?.refreshPings(notify: true) }
            },
        ]
    }

    private func refreshGame() async {
        guard let current = game else { return }
        guard let fresh: Game = try? await client.from("games").select()
            .eq("id", value: current.id.uuidString).single().execute().value
        else { return }
        let previous = game?.status
        game = fresh
        if previous != fresh.status {
            if fresh.status == .active { await refreshPlayers() }
            if fresh.status == .ended, previous == .active { announceResult(fresh) }
        }
        updateRoleServices()
    }

    private func refreshPlayers() async {
        guard let g = game else { return }
        guard let fresh: [Player] = try? await client.from("players").select()
            .eq("game_id", value: g.id.uuidString).order("joined_at").execute().value
        else { return }

        // Tell everyone when a runner goes down.
        if g.status == .active {
            for player in fresh where player.isCaught && player.role == .runner {
                let wasCaught = players.first { $0.userId == player.userId }?.isCaught ?? true
                if !wasCaught {
                    let who = player.userId == userId ? "You were" : "\(player.name) was"
                    NotificationManager.shared.notify(title: "🪤 \(who) caught!", body: "\(fresh.filter { $0.role == .runner && !$0.isCaught }.count) runner(s) left.")
                }
            }
        }
        players = fresh
        updateRoleServices()
    }

    private func refreshPings(notify: Bool) async {
        guard let g = game else { return }
        guard let fresh: [Ping] = try? await client.from("pings").select()
            .eq("game_id", value: g.id.uuidString)
            .order("created_at", ascending: false).limit(500).execute().value
        else { return }

        let new = fresh.filter { !seenPingIds.contains($0.id) }
        seenPingIds.formUnion(fresh.map(\.id))
        pings = fresh

        guard notify, me?.role == .hunter, !new.isEmpty else { return }
        for ping in new.reversed() where ping.kind == .vehicle {
            NotificationManager.shared.notify(
                title: "🚗 \(name(of: ping.runnerId)) is in a vehicle!",
                body: "Their live position is on your map. Go get them.",
                urgent: true
            )
        }
        if new.contains(where: { $0.kind == .scheduled }) {
            let names = Set(new.filter { $0.kind == .scheduled }.map { name(of: $0.runnerId) })
            NotificationManager.shared.notify(
                title: "📍 Runners revealed",
                body: "New locations for \(names.sorted().joined(separator: ", "))."
            )
        }
    }

    private func announceResult(_ g: Game) {
        switch g.winner {
        case .hunters?: NotificationManager.shared.notify(title: "🏁 Game over", body: "The hunters caught everyone!")
        case .runners?: NotificationManager.shared.notify(title: "🏁 Game over", body: "Time's up — the runners survived!")
        case nil: break
        }
    }

    // MARK: - Role services

    /// Starts/stops location + motion depending on who I am right now.
    private func updateRoleServices() {
        let desired: Role? = (game?.status == .active && me?.isCaught == false) ? me?.role : nil
        guard desired != activeRole else { return }
        stopRoleServices()
        activeRole = desired
        switch desired {
        case .runner?:
            location.start()
            motion.start()
        case .hunter?:
            location.start()
        case nil:
            break
        }
        tick()
    }

    private func stopRoleServices() {
        location.stop()
        motion.stop()
        activeRole = nil
    }

    private func startTicker() {
        ticker?.invalidate()
        // Fires in the background too, since background location keeps the app running.
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let g = game, g.status == .active else { return }
        let now = Date()

        if let ends = g.endsAt, now >= ends, !isFinishing {
            isFinishing = true
            Task {
                try? await client.rpc("finish_if_expired", params: GameIdParams(gameId: g.id)).execute()
                await refreshGame()
                isFinishing = false
            }
        }

        if activeRole == .runner {
            publishScheduledRevealIfDue(now: now)
            sendVehiclePingIfNeeded()
        }
    }

    // MARK: Runner

    private func handleLocation(_ loc: CLLocation) {
        guard activeRole == .runner else { return }
        motion.ingest(loc)
        tick()
    }

    private func handleVehicleDetected() {
        guard activeRole == .runner else { return }
        NotificationManager.shared.notify(
            title: "🚗 Vehicle detected",
            body: "The hunters have been pinged with your location. Get out and run!",
            urgent: true
        )
        sendVehiclePingIfNeeded()
    }

    /// Every 5 minutes (aligned to the end of the head start), reveal my location.
    private func publishScheduledRevealIfDue(now: Date) {
        guard let g = game, let huntStart = g.huntStartsAt, now >= huntStart,
              let loc = location.location, now.timeIntervalSince(loc.timestamp) < 120
        else { return }
        let slot = Int(now.timeIntervalSince(huntStart) / g.pingInterval)
        guard slot > lastPublishedSlot else { return }

        let previous = lastPublishedSlot
        lastPublishedSlot = slot
        UserDefaults.standard.set(slot, forKey: slotKey(g.id))
        Task {
            do {
                try await publishPing(loc, kind: .scheduled)
                lastRevealAt = Date()
            } catch {
                // Retry on the next tick.
                if lastPublishedSlot == slot { lastPublishedSlot = previous }
            }
        }
    }

    /// While in a vehicle, hunters get my location immediately and then every minute.
    private func sendVehiclePingIfNeeded() {
        guard activeRole == .runner, motion.isInVehicle, let loc = location.location else { return }
        if let last = lastVehiclePingAt, Date().timeIntervalSince(last) < Config.vehiclePingCooldown { return }
        lastVehiclePingAt = Date()
        Task {
            do { try await publishPing(loc, kind: .vehicle) } catch { lastVehiclePingAt = nil }
        }
    }

    private func publishPing(_ loc: CLLocation, kind: Ping.Kind) async throws {
        guard let g = game, let uid = userId else { return }
        let ping = NewPing(
            gameId: g.id, runnerId: uid,
            latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
            kind: kind
        )
        try await client.from("pings").insert(ping).execute()
    }

    // MARK: - Errors

    static func describe(_ error: Error) -> String {
        if let e = error as? PostgrestError { return e.message }
        return error.localizedDescription
    }
}
