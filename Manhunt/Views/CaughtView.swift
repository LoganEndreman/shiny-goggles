import SwiftUI

struct CaughtView: View {
    @EnvironmentObject private var service: GameService

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "hand.raised.slash.fill").font(.system(size: 72)).foregroundStyle(.red)
            Text("You've been caught").font(.largeTitle.bold())
            Text("It's over for you. \(service.runnersRemaining) runner(s) still out there.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Leave game") { Task { await service.leaveGame() } }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
