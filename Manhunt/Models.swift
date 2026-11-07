import Foundation
import CoreLocation

enum Role: String, Codable {
    case runner, hunter

    var title: String { self == .runner ? "Runner" : "Hunter" }
    var symbol: String { self == .runner ? "figure.run" : "binoculars.fill" }
}

enum Team: String, Codable {
    case runners, hunters
}

struct Game: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case lobby, active, ended }

    let id: UUID
    let code: String
    let hostId: UUID
    var status: Status
    let durationMinutes: Int
    let headStartMinutes: Int
    let pingIntervalSeconds: Int
    var startedAt: Date?
    var endsAt: Date?
    var winner: Team?

    enum CodingKeys: String, CodingKey {
        case id, code, status, winner
        case hostId = "host_id"
        case durationMinutes = "duration_minutes"
        case headStartMinutes = "head_start_minutes"
        case pingIntervalSeconds = "ping_interval_seconds"
        case startedAt = "started_at"
        case endsAt = "ends_at"
    }

    /// When the head start is over and scheduled reveals begin.
    var huntStartsAt: Date? {
        startedAt?.addingTimeInterval(TimeInterval(headStartMinutes * 60))
    }

    var pingInterval: TimeInterval { TimeInterval(pingIntervalSeconds) }

    /// The time of the next scheduled runner reveal after `date`.
    func nextReveal(after date: Date) -> Date? {
        guard let huntStart = huntStartsAt else { return nil }
        if date < huntStart { return huntStart }
        let slot = floor(date.timeIntervalSince(huntStart) / pingInterval)
        return huntStart.addingTimeInterval((slot + 1) * pingInterval)
    }
}

struct Player: Codable, Identifiable, Equatable {
    let gameId: UUID
    let userId: UUID
    var name: String
    var role: Role?
    var caughtAt: Date?
    let joinedAt: Date

    var id: UUID { userId }
    var isCaught: Bool { caughtAt != nil }

    enum CodingKeys: String, CodingKey {
        case name, role
        case gameId = "game_id"
        case userId = "user_id"
        case caughtAt = "caught_at"
        case joinedAt = "joined_at"
    }
}

struct Ping: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case scheduled, vehicle }

    let id: Int
    let gameId: UUID
    let runnerId: UUID
    let latitude: Double
    let longitude: Double
    let kind: Kind
    let createdAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, kind
        case gameId = "game_id"
        case runnerId = "runner_id"
        case createdAt = "created_at"
    }
}

struct NewPing: Encodable {
    let gameId: UUID
    let runnerId: UUID
    let latitude: Double
    let longitude: Double
    let kind: Ping.Kind

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, kind
        case gameId = "game_id"
        case runnerId = "runner_id"
    }
}

// MARK: - RPC parameters

struct CreateGameParams: Encodable {
    let name: String
    let duration: Int
    let headStart: Int
    enum CodingKeys: String, CodingKey {
        case name = "p_name", duration = "p_duration", headStart = "p_head_start"
    }
}

struct JoinGameParams: Encodable {
    let code: String
    let name: String
    enum CodingKeys: String, CodingKey { case code = "p_code", name = "p_name" }
}

struct GameIdParams: Encodable {
    let gameId: UUID
    enum CodingKeys: String, CodingKey { case gameId = "p_game_id" }
}

struct MarkCaughtParams: Encodable {
    let gameId: UUID
    let runnerId: UUID
    enum CodingKeys: String, CodingKey { case gameId = "p_game_id", runnerId = "p_runner_id" }
}
