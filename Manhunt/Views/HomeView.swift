import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var service: GameService
    @AppStorage("playerName") private var name = ""
    @State private var joinCode = ""
    @State private var duration = 60
    @State private var headStart = 5

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedCode: String { joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .onChange(of: name) { name = String(name.prefix(24)) }
                }

                Section {
                    TextField("Invite code", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced))
                    Button {
                        Task { await service.joinGame(code: trimmedCode, name: trimmedName) }
                    } label: {
                        Label("Join game", systemImage: "person.badge.plus")
                    }
                    .disabled(trimmedName.isEmpty || trimmedCode.count < 4)
                } header: {
                    Text("Join a friend")
                } footer: {
                    Text("Tap the invite link your friend sent, or type their code.")
                }

                Section("Host a game") {
                    Stepper("Game length: \(duration) min", value: $duration, in: 10...240, step: 10)
                    Stepper("Head start: \(headStart) min", value: $headStart, in: 0...30)
                    Button {
                        Task { await service.createGame(name: trimmedName, durationMinutes: duration, headStartMinutes: headStart) }
                    } label: {
                        Label("Create game", systemImage: "flag.checkered")
                    }
                    .disabled(trimmedName.isEmpty)
                }

                Section("Rules") {
                    RuleRow(symbol: "person.2.fill", text: "Everyone who joins is randomly split into Runners and Hunters when the host starts.")
                    RuleRow(symbol: "figure.run", text: "Runners must stay on foot. Get in a car and the Hunters are pinged instantly.")
                    RuleRow(symbol: "location.fill", text: "Hunters see every Runner's location every 5 minutes — and they can drive.")
                    RuleRow(symbol: "hand.raised.fill", text: "Caught? You're out. Hunters win if everyone is caught; Runners win if time runs out.")
                }
            }
            .navigationTitle("Manhunt")
            .disabled(service.isBusy)
            .overlay { if service.isBusy { ProgressView().controlSize(.large) } }
            .onAppear(perform: consumeInvite)
            .onChange(of: service.pendingJoinCode) { consumeInvite() }
        }
    }

    /// Opened from an invite link: fill the code and join right away if we know the name.
    private func consumeInvite() {
        guard let code = service.pendingJoinCode else { return }
        service.pendingJoinCode = nil
        joinCode = code
        if !trimmedName.isEmpty {
            Task { await service.joinGame(code: code, name: trimmedName) }
        }
    }
}

struct RuleRow: View {
    let symbol: String
    let text: String
    var body: some View {
        Label { Text(text).font(.subheadline) } icon: { Image(systemName: symbol).foregroundStyle(.tint) }
    }
}
