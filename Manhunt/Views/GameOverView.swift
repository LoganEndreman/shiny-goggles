import SwiftUI

struct GameOverView: View {
    @EnvironmentObject private var service: GameService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: headlineSymbol).font(.system(size: 64)).foregroundStyle(.tint)
                        Text(headline).font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text(subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                if service.game?.winner != nil {
                    Section("Hunters") {
                        ForEach(service.hunters) { Text($0.name) }
                    }
                    Section("Runners") {
                        ForEach(service.runners) { runner in
                            HStack {
                                Text(runner.name)
                                Spacer()
                                if let caught = runner.caughtAt, let start = service.game?.huntStartsAt {
                                    Text("caught after \(clock(max(0, caught.timeIntervalSince(start))))")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("escaped").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Game over")
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await service.leaveGame() }
                } label: {
                    Text("Back to home").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
    }

    private var myTeamWon: Bool {
        switch (service.game?.winner, service.me?.role) {
        case (.hunters?, .hunter?), (.runners?, .runner?): return true
        default: return false
        }
    }

    private var headline: String {
        guard service.game?.winner != nil else { return "Game cancelled" }
        return myTeamWon ? "You win!" : "You lose"
    }

    private var headlineSymbol: String {
        guard service.game?.winner != nil else { return "xmark.circle" }
        return myTeamWon ? "trophy.fill" : "flag.slash.fill"
    }

    private var subheadline: String {
        switch service.game?.winner {
        case .hunters?: return "The hunters caught every runner."
        case .runners?: return "Time ran out — \(service.runnersRemaining) runner(s) escaped."
        case nil: return "The host closed the lobby."
        }
    }
}
