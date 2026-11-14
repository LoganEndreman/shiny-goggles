import SwiftUI
import MapKit

struct RunnerView: View {
    @EnvironmentObject private var service: GameService
    @ObservedObject var location: LocationManager
    @ObservedObject var motion: MotionDetector
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var confirmingCaught = false

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }

            VStack(spacing: 8) {
                if motion.isInVehicle {
                    InfoCard {
                        Label("Vehicle detected!", systemImage: "car.fill")
                            .font(.headline).foregroundStyle(.red)
                        Text("The hunters were pinged and are getting your live location every minute until you're back on foot.")
                            .font(.subheadline)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if location.isDenied {
                    InfoCard {
                        Label("Location is off", systemImage: "location.slash")
                            .font(.headline).foregroundStyle(.orange)
                        Text("Turn on location in Settings — runners must share their position to play.")
                            .font(.subheadline)
                    }
                }
            }
            .padding(.top, 8)
            .animation(.spring, value: motion.isInVehicle)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let game = service.game {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        RevealCountdown(game: game, now: context.date)
                    }
                }
                HStack {
                    Label(motion.activityLabel, systemImage: "figure.walk.motion")
                    Spacer()
                    if let last = service.lastRevealAt {
                        Text("Last reveal \(last, style: .relative) ago")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)

                Button(role: .destructive) {
                    confirmingCaught = true
                } label: {
                    Label("I've been caught", systemImage: "hand.raised.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
            .padding()
            .background(.bar)
        }
        .confirmationDialog("Were you caught?", isPresented: $confirmingCaught, titleVisibility: .visible) {
            Button("Yes, I'm out", role: .destructive) {
                if let id = service.userId { Task { await service.markCaught(id) } }
            }
        } message: {
            Text("This can't be undone.")
        }
    }
}

struct RevealCountdown: View {
    let game: Game
    let now: Date

    var body: some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading) {
                if let huntStart = game.huntStartsAt, now < huntStart {
                    Text("Hunters released in").font(.caption).foregroundStyle(.secondary)
                    Text(clock(huntStart.timeIntervalSince(now))).font(.title2.monospacedDigit().bold())
                } else if let next = game.nextReveal(after: now) {
                    Text("Your location is revealed in").font(.caption).foregroundStyle(.secondary)
                    Text(clock(next.timeIntervalSince(now))).font(.title2.monospacedDigit().bold())
                }
            }
            Spacer()
        }
    }
}
