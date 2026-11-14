import SwiftUI

struct LobbyView: View {
    @EnvironmentObject private var service: GameService

    var body: some View {
        if let game = service.game {
            NavigationStack {
                List {
                    Section {
                        VStack(spacing: 12) {
                            Text("Invite code").font(.caption).foregroundStyle(.secondary)
                            Text(game.code)
                                .font(.system(size: 44, weight: .heavy, design: .monospaced))
                                .tracking(6)
                                .textSelection(.enabled)
                            if let url = service.inviteURL {
                                ShareLink(
                                    item: url,
                                    subject: Text("Join my Manhunt game"),
                                    message: Text("Join my Manhunt game! Tap the link or enter code \(game.code) in the Manhunt app.")
                                ) {
                                    Label("Invite friends", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    Section {
                        LabeledContent("Game length", value: "\(game.durationMinutes) min")
                        LabeledContent("Runner head start", value: "\(game.headStartMinutes) min")
                        LabeledContent("Runner reveals", value: "Every \(game.pingIntervalSeconds / 60) min")
                    }

                    Section {
                        ForEach(service.players) { player in
                            HStack {
                                Text(player.name)
                                if player.userId == service.userId { Text("(you)").foregroundStyle(.secondary) }
                                Spacer()
                                if player.userId == game.hostId {
                                    Image(systemName: "crown.fill").foregroundStyle(.yellow)
                                }
                            }
                        }
                    } header: {
                        Text("Players (\(service.players.count))")
                    } footer: {
                        Text("Teams are picked at random when the game starts: about half become Hunters, the rest Runners.")
                    }

                    PermissionsSection(location: service.location)
                }
                .navigationTitle("Lobby")
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        if service.isHost {
                            Button {
                                Task { await service.startGame() }
                            } label: {
                                Text(service.players.count < 2 ? "Waiting for players…" : "Start game")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(service.players.count < 2 || service.isBusy)
                        } else {
                            Label("Waiting for the host to start", systemImage: "hourglass")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.bar)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Leave", role: .destructive) { Task { await service.leaveGame() } }
                    }
                }
                .onAppear {
                    service.location.requestPermission()
                    service.motion.requestPermission()
                }
            }
        }
    }
}

struct PermissionsSection: View {
    @ObservedObject var location: LocationManager

    var body: some View {
        if !location.hasAlwaysPermission {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow location “Always”").font(.headline)
                        Text("Manhunt needs to keep tracking while your phone is locked so reveals and alerts keep working.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "location.slash.fill").foregroundStyle(.orange)
                }
                if location.isDenied || location.authorization == .authorizedWhenInUse {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } else {
                    Button("Allow location") { location.requestPermission() }
                }
            }
        }
    }
}
