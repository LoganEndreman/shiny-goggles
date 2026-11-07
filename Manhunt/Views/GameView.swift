import SwiftUI

struct GameView: View {
    @EnvironmentObject private var service: GameService

    var body: some View {
        if let game = service.game, let me = service.me {
            VStack(spacing: 0) {
                StatusBar(game: game, me: me, runnersRemaining: service.runnersRemaining, runnerCount: service.runners.count)
                Group {
                    if me.isCaught {
                        CaughtView()
                    } else if me.role == .runner {
                        RunnerView(location: service.location, motion: service.motion)
                    } else if me.role == .hunter {
                        HunterView()
                    } else {
                        ProgressView("Picking teams…").frame(maxHeight: .infinity)
                    }
                }
            }
        } else {
            ProgressView()
        }
    }
}

struct StatusBar: View {
    let game: Game
    let me: Player
    let runnersRemaining: Int
    let runnerCount: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 12) {
                Label(me.role?.title ?? "—", systemImage: me.role?.symbol ?? "questionmark")
                    .font(.headline)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(roleColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(roleColor)
                Spacer()
                timer(now: context.date)
                Spacer()
                Label("\(runnersRemaining)/\(runnerCount)", systemImage: "figure.run")
                    .font(.subheadline.monospacedDigit())
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var roleColor: Color { me.role == .hunter ? .red : .green }

    @ViewBuilder
    private func timer(now: Date) -> some View {
        if let huntStart = game.huntStartsAt, now < huntStart {
            VStack(spacing: 0) {
                Text("HEAD START").font(.caption2.bold()).foregroundStyle(.orange)
                Text(clock(huntStart.timeIntervalSince(now))).font(.title3.monospacedDigit().bold())
            }
        } else if let ends = game.endsAt {
            VStack(spacing: 0) {
                Text("TIME LEFT").font(.caption2.bold()).foregroundStyle(.secondary)
                Text(clock(ends.timeIntervalSince(now))).font(.title3.monospacedDigit().bold())
            }
        }
    }
}

/// Small card that floats over the map.
struct InfoCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
    }
}
