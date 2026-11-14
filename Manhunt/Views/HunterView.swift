import SwiftUI
import MapKit

struct HunterView: View {
    @EnvironmentObject private var service: GameService
    @State private var camera: MapCameraPosition = .automatic
    @State private var tagging: Player?

    private struct Marker: Identifiable {
        let runner: Player
        let ping: Ping
        var id: UUID { runner.userId }
    }

    private var markers: [Marker] {
        service.runners.filter { !$0.isCaught }.compactMap { runner in
            service.latestPing(for: runner.userId).map { Marker(runner: runner, ping: $0) }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                UserAnnotation()
                ForEach(markers) { marker in
                    Annotation(marker.runner.name, coordinate: marker.ping.coordinate) {
                        RunnerPin(ping: marker.ping)
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }

            if let game = service.game {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let huntStart = game.huntStartsAt, context.date < huntStart {
                        InfoCard {
                            Label("Runners are getting a head start", systemImage: "timer")
                                .font(.headline)
                            Text("First reveal in \(clock(huntStart.timeIntervalSince(context.date))). You'll still be alerted right away if anyone gets in a car.")
                                .font(.subheadline)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                if let game = service.game {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let next = game.nextReveal(after: context.date) {
                            Label("Next reveal in \(clock(next.timeIntervalSince(context.date)))", systemImage: "dot.radiowaves.left.and.right")
                                .font(.headline.monospacedDigit())
                        }
                    }
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(service.runners) { runner in
                            RunnerRow(runner: runner, ping: service.latestPing(for: runner.userId)) {
                                if let ping = service.latestPing(for: runner.userId) {
                                    withAnimation {
                                        camera = .region(MKCoordinateRegion(center: ping.coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
                                    }
                                }
                            } onTag: {
                                tagging = runner
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            .padding()
            .background(.bar)
        }
        .confirmationDialog(
            "Tag \(tagging?.name ?? "runner") as caught?",
            isPresented: Binding(get: { tagging != nil }, set: { if !$0 { tagging = nil } }),
            titleVisibility: .visible
        ) {
            Button("Caught!", role: .destructive) {
                if let runner = tagging { Task { await service.markCaught(runner.userId) } }
                tagging = nil
            }
        } message: {
            Text("Only tag someone you've actually caught. They'll be out of the game.")
        }
    }
}

struct RunnerPin: View {
    let ping: Ping
    var body: some View {
        Image(systemName: ping.kind == .vehicle ? "car.fill" : "figure.run")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(8)
            .background(Circle().fill(ping.kind == .vehicle ? Color.red : Color.orange))
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 3)
    }
}

struct RunnerRow: View {
    let runner: Player
    let ping: Ping?
    let onLocate: () -> Void
    let onTag: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(runner.name).font(.headline).strikethrough(runner.isCaught)
                Group {
                    if runner.isCaught {
                        Text("Caught")
                    } else if let ping {
                        Text("\(ping.kind == .vehicle ? "🚗 In a vehicle · " : "")seen \(ping.createdAt, style: .relative) ago")
                    } else {
                        Text("No location yet")
                    }
                }
                .font(.caption).foregroundStyle(ping?.kind == .vehicle && !runner.isCaught ? Color.red : Color.secondary)
            }
            Spacer()
            if !runner.isCaught {
                Button(action: onLocate) { Image(systemName: "scope") }
                    .buttonStyle(.bordered)
                    .disabled(ping == nil)
                Button("Tag", action: onTag)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
