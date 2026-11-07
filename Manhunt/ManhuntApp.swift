import SwiftUI

@main
struct ManhuntApp: App {
    @StateObject private var service = GameService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(service)
                .onOpenURL { service.handle(url: $0) }
                .task { await service.bootstrap() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var service: GameService

    var body: some View {
        Group {
            switch service.game?.status {
            case nil: HomeView()
            case .lobby?: LobbyView()
            case .active?: GameView()
            case .ended?: GameOverView()
            }
        }
        .animation(.default, value: service.game?.status)
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { service.errorMessage != nil },
                set: { if !$0 { service.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(service.errorMessage ?? "")
        }
    }
}
