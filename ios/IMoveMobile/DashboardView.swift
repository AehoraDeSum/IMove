import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var renew = true
    @State private var interval = 20
    @State private var devicePoint: Point?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Card {
                    HStack {
                        Circle().fill(store.status?.ready == true ? IMoveTheme.mint : .orange)
                            .frame(width: 10, height: 10)
                        Text(store.status?.ready == true ? "USB ready" : "Check the Mac connection")
                            .font(.headline)
                        Spacer()
                        if let status = store.status, status.routeID != "" {
                            Text("Route \(Int(status.routeProgress * 100))%")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    Text(store.message)
                        .font(.subheadline)
                        .foregroundColor(IMoveTheme.quiet)
                    if let status = store.status {
                        Text("Last command: \(status.lastSent.isEmpty ? "—" : status.lastSent)")
                            .font(.caption)
                            .foregroundColor(IMoveTheme.quiet)
                    }
                }

                Card {
                    Label("MAP", systemImage: "map.fill")
                        .font(.caption.weight(.bold)).foregroundColor(IMoveTheme.mint)
                    MapCanvas(selected: store.status?.routeID.isEmpty == false ? nil : store.selectedPoint,
                              sent: store.lastSentPoint, device: devicePoint) { point in
                        choose(point)
                    }
                    .frame(height: sizeClass == .regular ? 470 : 330)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text("Tap the map to choose a location.")
                        .font(.caption).foregroundColor(IMoveTheme.quiet)
                }

                Card {
                    Text("Send location").font(.title3.bold())
                    HStack {
                        field("Latitude", text: $latitude)
                        field("Longitude", text: $longitude)
                    }
                    Toggle("Keep refreshing on the Mac", isOn: $renew)
                    ActionButton(title: "Send selected location", icon: "paperplane.fill") {
                        guard let point = IMoveValidation.point(latitude: latitude, longitude: longitude) else { return }
                        Task { _ = await store.send(point, renew: renew) }
                    }
                    .disabled(IMoveValidation.point(latitude: latitude, longitude: longitude) == nil || store.connection == nil)
                    ActionButton(title: "Send this device's location", icon: "location.north.fill", secondary: true) {
                        Task { await store.sendDeviceLocation() }
                    }
                    .disabled(store.connection == nil)
                }

                Card {
                    Text("Quick places").font(.title3.bold())
                    if store.places.isEmpty {
                        Text("Add saved places from the Places tab.")
                            .foregroundColor(IMoveTheme.quiet)
                    } else {
                        ForEach(store.places.prefix(6)) { place in
                            Button {
                                choose(place.point)
                                Task { _ = await store.send(place.point, renew: renew) }
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
                                    Text(place.name)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(IMoveTheme.mint)
                        }
                    }
                }

                Card {
                    Text("Refresh and tracking").font(.title3.bold())
                    HStack {
                        Text("Mac refresh interval")
                        Spacer()
                        Picker("Seconds", selection: $interval) {
                            ForEach([1, 2, 5, 10, 20, 30, 60], id: \.self) { value in
                                Text("\(value) s").tag(value)
                            }
                        }
                        .labelsHidden()
                    }
                    ActionButton(title: "Apply refresh interval", icon: "arrow.clockwise", secondary: true) {
                        Task { _ = await store.perform { try await $0.setInterval(interval) } }
                    }
                    if store.status?.refreshing == true {
                        ActionButton(title: "Stop fixed refresh", icon: "pause.fill", secondary: true) {
                            Task { _ = await store.perform { try await $0.stopRenewal() } }
                        }
                    }
                    Divider()
                    Text("Track this device's location")
                        .font(.headline)
                    Text("When on, location updates from iOS are sent to the Mac at most every 5 minutes. iOS does not guarantee exact timing with the screen off, and it uses more battery.")
                        .font(.caption).foregroundColor(IMoveTheme.quiet)
                    ActionButton(title: store.tracking ? "Stop tracking" : "Start tracking",
                                 icon: store.tracking ? "stop.fill" : "location.fill",
                                 secondary: store.tracking) {
                        if store.tracking { store.stopTracking() }
                        else { Task { await store.startTracking() } }
                    }
                    .disabled(store.connection == nil)
                }

                Card {
                    ActionButton(title: "Remove simulated location", icon: "xmark.circle", secondary: true) {
                        Task { _ = await store.perform { try await $0.clear() } }
                    }
                    .disabled(store.connection == nil)
                }
            }
            .padding()
            .frame(maxWidth: sizeClass == .regular ? 1100 : 850)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("IMove")
        .imovePage()
        .task { await store.refreshAll() }
        .onReceive(store.deviceLocation.$point) { devicePoint = $0 }
        .onChange(of: store.selectedPoint) { point in
            if let point { latitude = String(point.latitude); longitude = String(point.longitude) }
        }
        .onChange(of: store.status?.updateIntervalSeconds) { value in
            if let value { interval = value }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.largeTitle).foregroundColor(IMoveTheme.mint)
            VStack(alignment: .leading) {
                Text("LOCATION CONTROL").font(.caption.weight(.bold)).foregroundColor(IMoveTheme.mint)
                Text("Control from iPhone and iPad").font(.subheadline).foregroundColor(IMoveTheme.quiet)
            }
        }
        .padding(.vertical, 8)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundColor(IMoveTheme.quiet)
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(IMoveTheme.background, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func choose(_ point: Point) {
        store.selectedPoint = point
        latitude = String(point.latitude)
        longitude = String(point.longitude)
    }
}
