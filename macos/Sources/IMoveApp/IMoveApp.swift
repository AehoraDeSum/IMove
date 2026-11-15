import SwiftUI
import AppKit
import MapKit
import IMoveCore

@main
struct IMoveApp: App {
    @StateObject private var model = AppModel(preferences: HostPreferences())
    @StateObject private var remote = RemoteServer()
    @StateObject private var startup = StartupOptions()

    var body: some Scene {
        Window("IMove · Hub", id: "main") {
            ContentView(model: model, remote: remote, startup: startup)
                .frame(minWidth: 900, minHeight: 660)
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    guard startup.beginBootstrap() else { return }
                    startup.refreshLoginItemStatus()
                    Task {
                        await model.restoreConnection()
                        if startup.startRemoteAtLaunch { remote.start(model: model) }
                    }
                }
        }
        .defaultSize(width: 1040, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("IMove Guide") { openGuide() }
            }
        }
    }
}

func openGuide() {
    if let url = Bundle.main.url(forResource: "Guide", withExtension: "html") {
        NSWorkspace.shared.open(url)
    }
}

enum Page: String, CaseIterable, Identifiable {
    case location = "Location"
    case map = "Map"
    case places = "Saved places"
    case routes = "Routes"
    case connection = "Connection"
    case remote = "Remote access"
    case history = "Activity log"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .location: return "location.circle"
        case .map: return "map"
        case .places: return "bookmark"
        case .routes: return "point.topleft.down.to.point.bottomright.curvepath"
        case .connection: return "cable.connector"
        case .remote: return "network"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

private let brand = Color(red: 0.29, green: 0.88, blue: 0.52)
private let navy = Color(red: 0.035, green: 0.105, blue: 0.075)
private let canvas = Color(red: 0.035, green: 0.075, blue: 0.057)
private let surface = Color(red: 0.075, green: 0.145, blue: 0.105)

@MainActor
final class NavigationState: ObservableObject {
    @Published var page: Page = .location
    @Published var showingErrorDetails = false
    @Published var placeName = ""
    @Published var libraryMessage: String?
    @Published var pendingDelete: UUID?
    @Published var pickedCoordinate: CLLocationCoordinate2D?
    @Published var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784),
                           span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
    @Published var routeName = ""
    @Published var routeTimingMode: RouteTimingMode = .equal
    @Published var routeTotalMinutes = 5
    @Published var routeTotalSecondsPart = 0
    @Published var routeSegmentSeconds: [Int] = []
    @Published var routeDraftPoints: [Coordinate] = []
    @Published var routeSegmentPaths: [[Coordinate]] = []
    @Published var routeSegmentDescriptions: [String] = []
    @Published var routeViaPoints: [[Coordinate]] = []
    @Published var routeEditingLeg: Int? = nil
    @Published var routeAddingVia = false
    @Published var railLineID = "B1"
    @Published var boardingIndex = 0
    @Published var alightingIndex = 1
    @Published var routeMessage: String?
    @Published var pendingRouteDelete: UUID?
    @Published var routeMapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784),
                           span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))

    var routeRequestedTotalSeconds: Int? {
        let (minutes, firstOverflow) = routeTotalMinutes.multipliedReportingOverflow(by: 60)
        let (total, secondOverflow) = minutes.addingReportingOverflow(routeTotalSecondsPart)
        return firstOverflow || secondOverflow ? nil : total
    }

    func appendRoutePoint(_ point: Coordinate, path: [Coordinate]? = nil,
                          description: String = "Hand-drawn segment", seconds: Int = 300) {
        if let previous = routeDraftPoints.last {
            routeSegmentPaths.append(path ?? [previous, point])
            routeSegmentDescriptions.append(description)
            routeViaPoints.append([])
            routeSegmentSeconds.append(seconds)
        }
        routeDraftPoints.append(point)
    }

    func undoRoutePoint() {
        guard !routeDraftPoints.isEmpty else { return }
        routeDraftPoints.removeLast()
        if !routeSegmentPaths.isEmpty { routeSegmentPaths.removeLast() }
        if !routeSegmentDescriptions.isEmpty { routeSegmentDescriptions.removeLast() }
        if !routeViaPoints.isEmpty { routeViaPoints.removeLast() }
        if !routeSegmentSeconds.isEmpty { routeSegmentSeconds.removeLast() }
        routeEditingLeg = nil
        routeAddingVia = false
    }

    func clearRoute() {
        routeDraftPoints = []
        routeSegmentPaths = []
        routeSegmentDescriptions = []
        routeViaPoints = []
        routeSegmentSeconds = []
        routeEditingLeg = nil
        routeAddingVia = false
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var remote: RemoteServer
    @ObservedObject var startup: StartupOptions
    @StateObject private var navigation = NavigationState()
    private let railCatalogue = RailCatalogue.load()
    private var page: Page {
        get { navigation.page }
        nonmutating set { navigation.page = newValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let error = model.errorMessage { errorBanner(error) }
                        switch page {
                        case .location: locationPage
                        case .map: mapPage
                        case .places: placesPage
                        case .routes: routesPage
                        case .connection: connectionPage
                        case .remote: remotePage
                        case .history: historyPage
                        }
                    }
                    .padding(30)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(canvas)
        }
        .tint(brand)
        .confirmationDialog("Remove the simulated location?", isPresented: $model.showResetConfirmation, titleVisibility: .visible) {
            Button("Remove simulated location", role: .destructive) { Task { await model.clear() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This may cause the iPhone to return to its real location. Check the result in the Find My app.")
        }
        .sheet(isPresented: $navigation.showingErrorDetails) {
            errorDetailsSheet
        }
        .confirmationDialog("Delete this saved place?", isPresented: Binding(
            get: { navigation.pendingDelete != nil }, set: { if !$0 { navigation.pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete place", role: .destructive) {
                if let id = navigation.pendingDelete {
                    do { try remote.removePlace(id: id); navigation.libraryMessage = "Place deleted." }
                    catch { navigation.libraryMessage = error.localizedDescription }
                }
                navigation.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { navigation.pendingDelete = nil }
        }
        .confirmationDialog("Delete this saved route?", isPresented: Binding(
            get: { navigation.pendingRouteDelete != nil },
            set: { if !$0 { navigation.pendingRouteDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete route", role: .destructive) {
                if let id = navigation.pendingRouteDelete {
                    do { try remote.removeRoute(id: id); navigation.routeMessage = "Route deleted." }
                    catch { navigation.routeMessage = error.localizedDescription }
                }
                navigation.pendingRouteDelete = nil
            }
            Button("Cancel", role: .cancel) { navigation.pendingRouteDelete = nil }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 31, weight: .medium)).foregroundStyle(brand)
                Text("IMove").font(.system(size: 29, weight: .semibold, design: .rounded))
            }.padding(.top, 42).padding(.bottom, 7)
            Text("YOUR LOCATION HUB")
                .font(.system(size: 9, weight: .semibold)).tracking(1.6)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 40)

            ForEach(Page.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon).font(.system(size: 17)).frame(width: 21)
                        Text(item.rawValue).font(.system(size: 14, weight: page == item ? .semibold : .regular))
                        Spacer()
                        if item == .history && !model.activities.isEmpty {
                            Text("\(model.activities.count)").font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .padding(.horizontal, 13).padding(.vertical, 13)
                    .background(page == item ? brand.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(page == item ? .white : .white.opacity(0.68))
                .padding(.bottom, 5)
                .accessibilityIdentifier("nav-\(item.id)")
            }
            Spacer(minLength: 30)
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "location.north.circle").font(.system(size: 22)).foregroundStyle(brand)
                Text("Everything in one place.").font(.system(size: 13, weight: .medium))
                Text("Manage locations and routes from all your devices.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineSpacing(4)
                Divider().overlay(.white.opacity(0.12))
                Text("MAC  /  1.1.0")
                    .font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(.white.opacity(0.45))
            }
            .padding(16)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 22)
        }
        .padding(.horizontal, 20)
        .frame(width: 224)
        .background(navy)
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack {
            Text(page.rawValue).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: model.transport == .demo ? "testtube.2" : "cable.connector")
                Text(model.transport == .demo ? "Test mode · No device affected" : "Real USB")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(brand.opacity(0.10), in: Capsule())
            .foregroundStyle(brand)
        }
        .padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 16)
    }

    private var locationPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your next location.")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(model.transport == .demo ? "Try it out here first. No iPhone connection needed." : "Send the chosen coordinate to the iPhone connected over USB.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            panel {
                VStack(alignment: .leading, spacing: 19) {
                    HStack {
                        Label("Choose location", systemImage: "mappin.and.ellipse").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("DECIMAL COORDINATES").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top, spacing: 18) {
                        coordinateField("Latitude", hint: "e.g. 41.0082", value: $model.latitude, id: "latitude")
                        coordinateField("Longitude", hint: "e.g. 28.9784", value: $model.longitude, id: "longitude")
                    }
                    .disabled(model.isBusy)
                    if let message = model.validationMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.system(size: 12)).foregroundStyle(.red)
                    } else {
                        Text("Use a dot or a comma. Order: latitude, longitude.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Text("Saved places").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        if remote.places.isEmpty {
                            Text("Nothing saved yet").font(.system(size: 11)).foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    ForEach(remote.places, id: \.id) { place in
                                        Button(place.name) {
                                            model.latitude = String(place.latitude)
                                            model.longitude = String(place.longitude)
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(brand)
                                        .padding(.horizontal, 11).padding(.vertical, 6)
                                        .background(brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(brand.opacity(0.3)))
                                    }
                                }
                            }
                        }
                        Button("Add place →") { page = .places }
                            .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
                    }.disabled(model.isBusy)
                    Divider()
                    HStack(spacing: 12) {
                        Button { Task { await model.send() } } label: {
                            HStack(spacing: 7) {
                                if model.isBusy { ProgressView().controlSize(.small) }
                                else { Image(systemName: "arrow.up.right") }
                                Text(model.transport == .demo ? "Send test location" : "Send to iPhone")
                            }
                            .padding(.horizontal, 6).padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canSend)
                        .accessibilityIdentifier("send-coordinate")
                        Button(model.transport == .demo ? "Clear test location" : "Remove simulated location") {
                            if model.transport == .demo { Task { await model.clear() } }
                            else { model.showResetConfirmation = true }
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isBusy || !model.hasTarget || (model.transport == .demo && model.lastCommand == nil))
                        .accessibilityIdentifier("clear-coordinate")
                    }
                    if model.transport == .usb {
                        Toggle("Auto-refresh the location I send", isOn: Binding(
                            get: { model.keepLocationActive },
                            set: { model.setKeepLocationActive($0) }
                        ))
                        .font(.system(size: 12))
                        .disabled(model.isBusy)
                        updateIntervalPicker
                        Text("Off by default. When on, the Mac resends the same location starting from the next send. The actual interval depends on how long the USB command takes.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if model.transport == .usb && model.isMaintainingLocation {
                        HStack(spacing: 10) {
                            Label("Auto-refresh on · at most every \(model.updateIntervalSeconds) seconds", systemImage: "arrow.clockwise.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("Stop refreshing") { model.stopRefreshing() }
                                .buttonStyle(.borderless)
                                .disabled(model.isBusy)
                                .accessibilityIdentifier("stop-refreshing")
                        }
                        .foregroundStyle(brand)
                        Text("Keep the Mac and USB connection on. Pausing does not clear the simulated location; check the result in Find My.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if model.transport == .usb && !model.hasTarget {
                        Button("Prepare the USB connection first →") { page = .connection }
                            .buttonStyle(.borderless).font(.system(size: 12))
                    }
                }
            }
            statusPanel
            if model.transport == .demo {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("When you are ready, choose the iPhone on the Connection screen. With remote access you can manage locations and routes from Android, iPhone or iPad.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }
            }
        }
    }

    private var mapPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick on the map.").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Click the map to choose a point. The last sent coordinate is marked too; the iPhone's live location is not read.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            panel {
                VStack(alignment: .leading, spacing: 14) {
                    if let last = model.lastCommand {
                        Button("Go to last sent coordinate") {
                            navigation.mapPosition = .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))
                        }.buttonStyle(.borderless)
                    }
                    MapReader { proxy in
                        Map(position: $navigation.mapPosition) {
                            if let last = model.lastCommand {
                                Marker("Last sent", systemImage: "location.fill",
                                       coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude))
                                    .tint(.blue)
                            }
                            if let pickedCoordinate = navigation.pickedCoordinate {
                                Marker("Selected point", systemImage: "mappin",
                                       coordinate: pickedCoordinate).tint(brand)
                            }
                        }
                        .onTapGesture { point in
                            if let coordinate = proxy.convert(point, from: .local),
                               (-90...90).contains(coordinate.latitude),
                               (-180...180).contains(coordinate.longitude) {
                                navigation.pickedCoordinate = coordinate
                                model.latitude = String(format: "%.6f", coordinate.latitude)
                                model.longitude = String(format: "%.6f", coordinate.longitude)
                                navigation.libraryMessage = "The selected point was copied into the coordinate fields."
                            }
                        }
                    }
                    .frame(height: 390)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    HStack {
                        Text(navigation.pickedCoordinate.map { String(format: "Selected: %.6f, %.6f", $0.latitude, $0.longitude) }
                             ?? "Click the map to choose a point.")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Add to saved places") { page = .places }
                            .disabled(navigation.pickedCoordinate == nil)
                        Button(model.transport == .demo ? "Send test location" : "Send to iPhone") {
                            Task { await model.send() }
                        }
                        .buttonStyle(.borderedProminent).disabled(!model.canSend)
                    }
                }
            }
            if let libraryMessage = navigation.libraryMessage { Text(libraryMessage).font(.system(size: 12)).foregroundStyle(.secondary) }
            statusPanel
        }
        .onAppear {
            if navigation.pickedCoordinate == nil, let last = model.lastCommand {
                navigation.mapPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))
            }
        }
    }

    private var placesPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your favorite places.").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Places are stored on this Mac and appear on Android, iPad and iPhone with the same pairing code.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            panel {
                VStack(alignment: .leading, spacing: 16) {
                    Label("New place", systemImage: "plus.circle").font(.system(size: 15, weight: .semibold))
                    TextField("Place name (e.g. home)", text: $navigation.placeName).textFieldStyle(.roundedBorder)
                    HStack(spacing: 12) {
                        coordinateField("Latitude", hint: "41.0082", value: $model.latitude, id: "place-latitude")
                        coordinateField("Longitude", hint: "28.9784", value: $model.longitude, id: "place-longitude")
                    }
                    HStack {
                        Button("Pick on map") { page = .map }.buttonStyle(.bordered)
                        Spacer()
                        Button("Save place") {
                            do {
                                guard let coordinate = model.coordinate else {
                                    navigation.libraryMessage = model.validationMessage ?? "Enter a valid coordinate."
                                    return
                                }
                                try remote.addPlace(name: navigation.placeName, coordinate: coordinate)
                                navigation.placeName = ""
                                navigation.libraryMessage = "Place saved."
                            } catch { navigation.libraryMessage = error.localizedDescription }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            if let libraryMessage = navigation.libraryMessage { Text(libraryMessage).font(.system(size: 12)).foregroundStyle(.secondary) }
            if let error = remote.errorMessage { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            panel {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved places · \(remote.places.count)").font(.system(size: 15, weight: .semibold))
                        .padding(.bottom, 10)
                    if remote.places.isEmpty {
                        Text("No places saved yet.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    ForEach(remote.places, id: \.id) { place in
                        Divider().padding(.vertical, 9)
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(brand).font(.system(size: 21))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(place.name).font(.system(size: 14, weight: .semibold))
                                Text(String(format: "%.6f, %.6f", place.latitude, place.longitude))
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Show on map") {
                                let point = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                                navigation.pickedCoordinate = point
                                navigation.mapPosition = .region(MKCoordinateRegion(center: point,
                                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))
                                page = .map
                            }
                            Button(model.transport == .demo ? "Test" : "Send to iPhone") {
                                model.latitude = String(place.latitude)
                                model.longitude = String(place.longitude)
                                Task { await model.send() }
                            }
                            .disabled(model.isBusy || !model.hasTarget)
                            .buttonStyle(.borderedProminent)
                            Button("Delete", role: .destructive) { navigation.pendingDelete = place.id }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private var railBuilder: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Istanbul rail transit", systemImage: "tram.fill")
                .font(.system(size: 15, weight: .semibold))
            Text("Line geometry is approximate map data, not live train or timetable information. Review durations before saving.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Walking paths are calculated online; if Apple Maps does not respond, FOSSGIS Valhalla is used.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let catalogue = railCatalogue,
               let line = catalogue.lines.first(where: { $0.id == navigation.railLineID }) {
                HStack {
                    Picker("Line", selection: $navigation.railLineID) {
                        ForEach(catalogue.lines) { item in
                            Text("\(item.id) · \(item.name)").tag(item.id)
                        }
                    }.onChange(of: navigation.railLineID) { _, _ in
                        navigation.boardingIndex = 0
                        navigation.alightingIndex = 1
                    }
                    Picker("Board at", selection: $navigation.boardingIndex) {
                        ForEach(line.stations.indices, id: \.self) { index in
                            Text(line.stations[index].name).tag(index)
                        }
                    }
                    Picker("Alight at", selection: $navigation.alightingIndex) {
                        ForEach(line.stations.indices, id: \.self) { index in
                            Text(line.stations[index].name).tag(index)
                        }
                    }
                }
                HStack {
                    Button("Walk to boarding station") {
                        let station = line.stations[navigation.boardingIndex].coordinate
                        guard let last = navigation.routeDraftPoints.last else {
                            navigation.appendRoutePoint(station)
                            navigation.routeMessage = "Boarding station added as the starting point."
                            return
                        }
                        Task {
                            do {
                                let result = try await WalkingRouter.calculate([last, station])
                                guard navigation.routeDraftPoints.last == last else {
                                    navigation.routeMessage = "The route changed; start the walking calculation again."
                                    return
                                }
                                navigation.appendRoutePoint(station, path: result.path,
                                                            description: "Walk · \(line.stations[navigation.boardingIndex].name)",
                                                            seconds: max(1, min(86_400, result.seconds)))
                                navigation.routeMessage = "Walking segment added."
                            } catch { navigation.routeMessage = error.localizedDescription }
                        }
                    }
                    Button("Add line to route") { addRailSection(line) }
                        .buttonStyle(.borderedProminent)
                        .disabled(navigation.boardingIndex == navigation.alightingIndex)
                    Text("Transfers at Levent and Yenikapı are connected automatically.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Text("Could not load line data.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func addRailSection(_ line: RailLine) {
        guard let sections = line.section(from: navigation.boardingIndex, to: navigation.alightingIndex),
              let first = sections.first else {
            navigation.routeMessage = "Choose the boarding and alighting stations."
            return
        }
        let origin = first.0
        if let previous = navigation.routeDraftPoints.last, previous != origin {
            let meters = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude))
            guard meters <= 400 else {
                navigation.routeMessage = "The boarding station is far away. First add a connection with 'Walk to boarding station'."
                return
            }
            navigation.appendRoutePoint(origin, description: "Transfer · short walk (approximate)",
                                        seconds: max(60, Int(meters / 1.2)))
        } else if navigation.routeDraftPoints.isEmpty {
            navigation.appendRoutePoint(origin)
        }
        for (_, end, path, description) in sections {
            navigation.appendRoutePoint(end, path: path, description: description,
                                        seconds: line.id == "B1" ? 150 : 120)
        }
        navigation.routeTotalMinutes = max(navigation.routeTotalMinutes,
                                            (navigation.routeSegmentSeconds.reduce(0, +) + 59) / 60)
        navigation.routeMapPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
        navigation.routeMessage = "\(line.id) · \(sections.count) station segments added. Review the durations."
    }

    private var routesPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Draw your route.").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Pick points on the map, calculate walking paths or add Istanbul rail lines. You can reshape the path with waypoints.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            panel {
                VStack(alignment: .leading, spacing: 8) {
                    updateIntervalPicker
                    Text("Route waypoints and the final-point refresh after completion use this interval. If a previous USB command is still running, the new one waits.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            panel {
                VStack(alignment: .leading, spacing: 15) {
                    railBuilder
                    Divider()
                    HStack {
                        Label("Route points", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("\(navigation.routeDraftPoints.count) points")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    MapReader { proxy in
                        Map(position: $navigation.routeMapPosition) {
                            if navigation.routeDraftPoints.count >= 2 {
                                MapPolyline(coordinates: (navigation.routeSegmentPaths.isEmpty
                                    ? navigation.routeDraftPoints
                                    : navigation.routeSegmentPaths.flatMap { $0 }).map {
                                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                                }).stroke(brand, lineWidth: 3)
                            }
                            ForEach(Array(navigation.routeDraftPoints.enumerated().filter { $0.offset == 0 || $0.offset == navigation.routeDraftPoints.count - 1 || $0.offset % max(1, (navigation.routeDraftPoints.count + 99) / 100) == 0 }), id: \.offset) { index, point in
                                Marker("Point \(index + 1)", coordinate: CLLocationCoordinate2D(
                                    latitude: point.latitude, longitude: point.longitude)).tint(brand)
                            }
                        }
                        .onTapGesture { position in
                            guard let coordinate = proxy.convert(position, from: .local),
                                  let point = try? Coordinate(latitude: String(coordinate.latitude),
                                                              longitude: String(coordinate.longitude)) else { return }
                            if navigation.routeAddingVia, let leg = navigation.routeEditingLeg,
                               navigation.routeSegmentPaths.indices.contains(leg) {
                                navigation.routeViaPoints[leg].append(point)
                                navigation.routeSegmentPaths[leg] = [navigation.routeDraftPoints[leg]] +
                                    navigation.routeViaPoints[leg] + [navigation.routeDraftPoints[leg + 1]]
                                navigation.routeSegmentDescriptions[leg] = "Hand-edited segment"
                                navigation.routeMessage = "Waypoint added to segment \(leg + 1)."
                            } else {
                                navigation.appendRoutePoint(point)
                                navigation.routeMessage = "Point \(navigation.routeDraftPoints.count) added."
                            }
                        }
                    }
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    HStack {
                        Text("The first point is the start, the last point is the destination.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Undo last point") {
                            navigation.undoRoutePoint()
                        }
                            .disabled(navigation.routeDraftPoints.isEmpty)
                        Button("Clear draft") {
                            navigation.clearRoute()
                        }
                            .disabled(navigation.routeDraftPoints.isEmpty)
                    }
                    if !navigation.routeDraftPoints.isEmpty {
                        DisclosureGroup("Point list") {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 5) {
                                    ForEach(Array(navigation.routeDraftPoints.enumerated()), id: \.offset) { index, point in
                                        Text("\(index + 1). \(point.label)" +
                                             (index > 0 && navigation.routeSegmentDescriptions.indices.contains(index - 1)
                                              ? " · \(navigation.routeSegmentDescriptions[index - 1])" : ""))
                                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                }
                            }.frame(maxHeight: 180)
                        }
                    }
                    if !navigation.routeSegmentPaths.isEmpty {
                        HStack {
                            Picker("Segment to edit", selection: Binding(
                                get: { navigation.routeEditingLeg ?? 0 },
                                set: { navigation.routeEditingLeg = $0 })) {
                                ForEach(navigation.routeSegmentPaths.indices, id: \.self) { index in
                                    Text("\(index + 1) → \(index + 2)").tag(index)
                                }
                            }.frame(maxWidth: 240)
                            Button(navigation.routeAddingVia ? "Finish adding waypoints" : "Add waypoints on map") {
                                if navigation.routeEditingLeg == nil { navigation.routeEditingLeg = 0 }
                                navigation.routeAddingVia.toggle()
                            }
                            Button("Calculate walking path") {
                                let leg = navigation.routeEditingLeg ?? 0
                                guard navigation.routeSegmentPaths.indices.contains(leg) else { return }
                                Task {
                                    do {
                                        let via = [navigation.routeDraftPoints[leg]] + navigation.routeViaPoints[leg] +
                                            [navigation.routeDraftPoints[leg + 1]]
                                        let result = try await WalkingRouter.calculate(via)
                                        guard navigation.routeSegmentPaths.indices.contains(leg),
                                              navigation.routeDraftPoints[leg] == via.first,
                                              navigation.routeDraftPoints[leg + 1] == via.last else {
                                            navigation.routeMessage = "The route changed; start the walking calculation again."
                                            return
                                        }
                                        navigation.routeSegmentPaths[leg] = result.path
                                        navigation.routeSegmentDescriptions[leg] = "Walk · follows streets"
                                        navigation.routeSegmentSeconds[leg] = max(1, min(86_400, result.seconds))
                                        navigation.routeAddingVia = false
                                        navigation.routeMessage = "Walking path calculated."
                                    } catch { navigation.routeMessage = error.localizedDescription }
                                }
                            }
                        }
                        Text("While waypoint mode is on, map clicks reshape the selected segment. The walking calculation passes through the waypoints.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Divider()
                    TextField("Route name", text: $navigation.routeName).textFieldStyle(.roundedBorder)
                    Picker("Timing", selection: $navigation.routeTimingMode) {
                        Text("Split total time evenly").tag(RouteTimingMode.equal)
                        Text("Set each segment separately").tag(RouteTimingMode.custom)
                    }.pickerStyle(.segmented)
                    if navigation.routeTimingMode == .equal {
                        HStack {
                            Text("Total duration")
                            TextField("Minutes", value: $navigation.routeTotalMinutes, format: .number)
                                .frame(width: 70).textFieldStyle(.roundedBorder)
                            Text("dk")
                            TextField("Seconds", value: $navigation.routeTotalSecondsPart, format: .number)
                                .frame(width: 65).textFieldStyle(.roundedBorder)
                            Text("sn")
                        }
                        Text("The total duration is split evenly across segments; each segment must be at least 1 second.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 7) {
                                ForEach(navigation.routeSegmentSeconds.indices, id: \.self) { index in
                                    HStack {
                                        Text("\(index + 1) → \(index + 2)").frame(width: 65, alignment: .leading)
                                        TextField("Minutes", value: Binding(
                                            get: { navigation.routeSegmentSeconds[index] / 60 },
                                            set: { navigation.routeSegmentSeconds[index] = min(1440, max(0, $0)) * 60 + navigation.routeSegmentSeconds[index] % 60 }), format: .number)
                                            .frame(width: 70).textFieldStyle(.roundedBorder)
                                        Text("dk")
                                        TextField("Seconds", value: Binding(
                                            get: { navigation.routeSegmentSeconds[index] % 60 },
                                            set: { navigation.routeSegmentSeconds[index] = navigation.routeSegmentSeconds[index] / 60 * 60 + min(59, max(0, $0)) }), format: .number)
                                            .frame(width: 65).textFieldStyle(.roundedBorder)
                                        Text("sn")
                                    }
                                }
                            }
                        }.frame(maxHeight: 260)
                    }
                    Text("Total duration: \(RouteTiming.label(navigation.routeTimingMode == .equal ? max(0, navigation.routeRequestedTotalSeconds ?? 0) : navigation.routeSegmentSeconds.reduce(0, +)))")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Save route") {
                            do {
                                let total = navigation.routeRequestedTotalSeconds
                                guard navigation.routeTimingMode == .custom ||
                                      (total != nil && navigation.routeTotalMinutes >= 0 &&
                                       (0...59).contains(navigation.routeTotalSecondsPart)) else {
                                    throw IMoveError.message("Enter the total duration as valid minutes and seconds.")
                                }
                                let durations = navigation.routeTimingMode == .equal
                                    ? RouteTiming.distributed(totalSeconds: total ?? 0, segments: navigation.routeDraftPoints.count - 1) ?? []
                                    : navigation.routeSegmentSeconds
                                try remote.addRoute(name: navigation.routeName,
                                                    timingMode: navigation.routeTimingMode,
                                                    segmentDurationsSeconds: durations,
                                                    points: navigation.routeDraftPoints,
                                                    segmentPaths: navigation.routeSegmentPaths,
                                                    segmentDescriptions: navigation.routeSegmentDescriptions)
                                navigation.routeName = ""
                                navigation.clearRoute()
                                navigation.routeMessage = "Route saved."
                            } catch { navigation.routeMessage = error.localizedDescription }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(navigation.routeDraftPoints.count < 2)
                    }
                }
            }
            if let routeMessage = navigation.routeMessage {
                Text(routeMessage).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if model.activeRouteID != nil {
                panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active route: \(model.activeRouteName)").font(.system(size: 15, weight: .semibold))
                        ProgressView(value: model.routeProgress)
                        Text("\(Int(model.routeProgress * 100))% · \(model.routeSegmentIndex) / \(model.routeSegmentCount) segments")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Stop route") { Task { await model.stopRoute() } }
                            .buttonStyle(.bordered)
                        Text("Stopping does not clear the last sent location; the Mac keeps auto-refreshing.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            panel {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved routes · \(remote.routes.count)")
                        .font(.system(size: 15, weight: .semibold)).padding(.bottom, 10)
                    if remote.routes.isEmpty {
                        Text("No routes saved yet.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    ForEach(remote.routes, id: \.id) { route in
                        Divider().padding(.vertical, 10)
                        HStack {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                .foregroundStyle(brand).font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(route.name).font(.system(size: 14, weight: .semibold))
                                Text("\(route.points.count) points · \(route.timingMode == .equal ? "even" : "custom") timing · total \(RouteTiming.label(route.totalDurationSeconds))")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open on map") {
                                navigation.routeDraftPoints = route.points.map(\.coordinate)
                                navigation.routeSegmentPaths = route.segmentPaths.isEmpty
                                    ? zip(route.points, route.points.dropFirst()).map { [$0.coordinate, $1.coordinate] }
                                    : route.segmentPaths.map { $0.map(\.coordinate) }
                                navigation.routeSegmentDescriptions = route.segmentDescriptions.isEmpty
                                    ? Array(repeating: "Hand-drawn segment", count: route.points.count - 1)
                                    : route.segmentDescriptions
                                navigation.routeViaPoints = Array(repeating: [], count: route.points.count - 1)
                                navigation.routeName = ""
                                navigation.routeTimingMode = route.timingMode
                                navigation.routeTotalMinutes = route.totalDurationSeconds / 60
                                navigation.routeTotalSecondsPart = route.totalDurationSeconds % 60
                                navigation.routeSegmentSeconds = route.segmentDurationsSeconds
                                if let first = route.points.first {
                                    let latitudes = route.points.map(\.latitude)
                                    let longitudes = route.points.map(\.longitude)
                                    let minLatitude = latitudes.min() ?? first.latitude
                                    let maxLatitude = latitudes.max() ?? first.latitude
                                    let minLongitude = longitudes.min() ?? first.longitude
                                    let maxLongitude = longitudes.max() ?? first.longitude
                                    navigation.routeMapPosition = .region(MKCoordinateRegion(
                                        center: CLLocationCoordinate2D(latitude: (minLatitude + maxLatitude) / 2,
                                                                       longitude: (minLongitude + maxLongitude) / 2),
                                        span: MKCoordinateSpan(latitudeDelta: max(0.02, (maxLatitude - minLatitude) * 1.3),
                                                               longitudeDelta: max(0.02, (maxLongitude - minLongitude) * 1.3))))
                                }
                            }
                            Button(model.transport == .demo ? "Test" : "Start") {
                                Task {
                                    do { try await model.startRoute(route); navigation.routeMessage = "Route started." }
                                    catch { navigation.routeMessage = error.localizedDescription }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy || model.activeRouteID != nil || !model.hasTarget)
                            Button("Delete", role: .destructive) { navigation.pendingRouteDelete = route.id }
                                .disabled(model.activeRouteID == route.id)
                        }
                    }
                }
            }
            statusPanel
        }
    }

    private var statusPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.errorMessage == nil ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle")
                        .font(.system(size: 21)).foregroundStyle(model.errorMessage == nil ? brand : .red)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.status).font(.system(size: 15, weight: .semibold))
                        Text(model.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    Spacer(minLength: 0)
                }
                if let point = model.lastCommand {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.transport == .demo ? "LAST TEST LOCATION" : "LAST SENT COMMAND")
                                .font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                            Text(point.label).font(.system(size: 19, weight: .medium, design: .monospaced)).textSelection(.enabled)
                        }
                        Spacer()
                        if let time = model.lastCommandDate {
                            Text(time, style: .time).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.transport == .usb {
                    if let duration = model.lastSuccessfulUSBSetDurationSeconds {
                        Label("Last successful USB send: ~\(Int((duration * 1_000).rounded())) ms", systemImage: "timer")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let time = model.lastRefreshDate {
                        Label("Last auto-refresh: \(time.formatted(date: .omitted, time: .shortened)) · \(model.refreshCount) times", systemImage: "arrow.clockwise")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var updateIntervalPicker: some View {
        Picker("USB send interval", selection: Binding(
            get: { model.updateIntervalSeconds },
            set: { try? model.setUpdateIntervalSeconds($0) }
        )) {
            ForEach(Array(Set([1, 2, 5, 10, 20, 30, 60, model.updateIntervalSeconds])).sorted(), id: \.self) { seconds in
                Text("\(seconds) seconds").tag(seconds)
            }
        }
        .pickerStyle(.menu)
        .disabled(model.isBusy)
    }

    private var connectionPage: some View {
        VStack(alignment: .leading, spacing: 23) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set up your connection.").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Choose the iPhone connected over USB and prepare the connection.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            panel {
                VStack(alignment: .leading, spacing: 17) {
                    Text("Mode").font(.system(size: 15, weight: .semibold))
                    Picker("Mode", selection: Binding(get: { model.transport }, set: { model.changeTransport($0) })) {
                        ForEach(Transport.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().disabled(model.isBusy)
                    Text("Switching modes does not remove the current iPhone location. You can enable finding the USB target at launch on the Remote access screen.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    if model.transport == .demo {
                        Divider()
                        Toggle("Simulate a connection error", isOn: $model.simulateFailure).disabled(model.isBusy)
                        Text("When on, send and clear operations return a sample connection error.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            if model.transport == .usb {
                panel {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("USB tool", systemImage: "cable.connector").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("READY").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(brand)
                        }
                        Text("The USB tool is bundled with the app. The iPhone may need the developer image prepared.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                        Label(model.toolPath.isEmpty ? "USB tool not found" : "USB tool ready · pymobiledevice3 11.19.1",
                              systemImage: model.toolPath.isEmpty ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(model.toolPath.isEmpty ? .yellow : brand)
                        DisclosureGroup("Advanced tool selection") {
                            HStack {
                                Text(model.toolPath).font(.system(size: 10, design: .monospaced))
                                    .lineLimit(2).textSelection(.enabled)
                                Spacer()
                                Button("Choose another tool…") { model.chooseTool() }.disabled(model.isBusy)
                            }
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        Divider()
                        HStack {
                            Button { Task { await model.scan() } } label: {
                                Label(model.isBusy ? "Working…" : "Scan USB devices", systemImage: "arrow.clockwise")
                            }.disabled(model.isBusy || model.toolPath.isEmpty)
                            Spacer()
                            if let time = model.scannedAt {
                                Text("Last scan: \(time.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        if !model.devices.isEmpty {
                            Picker("Target device", selection: Binding(get: { model.selectedDeviceID }, set: { model.selectDevice($0) })) {
                                Text("Choose device…").tag("")
                                if !model.selectedDeviceID.isEmpty && !model.devices.contains(where: { $0.id == model.selectedDeviceID }) {
                                    Text("Saved target · not connected").tag(model.selectedDeviceID)
                                }
                                ForEach(model.devices) { device in Text(device.id).tag(device.id) }
                            }.disabled(model.isBusy)
                            Text("Compare the ID with the iPhone you want to connect. A scan only shows the USB devices present at that moment.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if !model.selectedDeviceID.isEmpty && !model.hasTarget {
                            Text("Expected iPhone: \(model.selectedDeviceID) · not connected right now")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.yellow)
                        }
                        Divider()
                        HStack(alignment: .center, spacing: 13) {
                            Button { Task { await model.mountDeveloperImage() } } label: {
                                Label("Mount developer image", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isBusy || !model.hasTarget)
                            .accessibilityIdentifier("mount-developer-image")
                            Text("Works on the selected iPhone. Downloads the matching image if needed; this can take a few minutes.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                panel {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("First connection").font(.system(size: 15, weight: .semibold))
                        Text("1. Connect the iPhone, unlock it and trust this Mac.\n2. Scan USB devices and choose the iPhone.\n3. Mount the developer image if needed.\n4. Send a location and check the result in Find My on another device.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(6)
                        Button("Open setup guide", action: openGuide).buttonStyle(.borderless)
                    }
                }
            } else {
                statusPanel
            }
        }
    }

    private var remotePage: some View {
        VStack(alignment: .leading, spacing: 23) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Control it from your phone.")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Android, iPhone and iPad browsers can all open the same control page.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            panel {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Mac control page", systemImage: "network")
                        .font(.system(size: 15, weight: .semibold))
                    Text(remote.isRunning ? "Running on this Mac · 127.0.0.1:8765" : "Off")
                        .font(.system(size: 13, weight: .medium))
                    Text("The page only listens on this Mac's own address. To reach it from your phone, set up the private network connection described in the guide.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 11) {
                        if remote.isRunning || remote.isStarting {
                            Button("Stop control page") { remote.stop() }
                                .buttonStyle(.bordered)
                        } else {
                            Button("Start control page") { remote.start(model: model) }
                                .buttonStyle(.borderedProminent)
                        }
                        if remote.isRunning {
                            Button("Try on this Mac") {
                                NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765/")!)
                            }.buttonStyle(.borderless)
                        }
                    }
                    if let error = remote.errorMessage {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    }
                    if remote.isRunning {
                        Divider()
                        Text("PAIRING CODE")
                            .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                        Text(remote.pairingCode)
                            .font(.system(size: 18, design: .monospaced)).textSelection(.enabled)
                        Button("Copy code") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(remote.pairingCode, forType: .string)
                        }.buttonStyle(.borderless)
                        Text("Only use this code on your own devices. The control page runs as long as the app stays open on the Mac.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            panel {
                VStack(alignment: .leading, spacing: 13) {
                    Label("Mac startup", systemImage: "power")
                        .font(.system(size: 15, weight: .semibold))
                    Toggle("Launch IMove at login", isOn: Binding(
                        get: { startup.isLoginItemRegistered },
                        set: { startup.setLaunchAtLogin($0) }
                    ))
                    Toggle("Find the selected USB target at launch", isOn: Binding(
                        get: { startup.restoreUSBAtLaunch },
                        set: { startup.setRestoreUSB($0) }
                    ))
                    Toggle("Start the control page at launch", isOn: Binding(
                        get: { startup.startRemoteAtLaunch },
                        set: { startup.setStartRemote($0) }
                    ))
                    Text("Auto-launch runs after you log in to the Mac. The USB target is verified; previous route or location commands are not resent automatically. Tailscale must also be connected.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if model.toolPath.isEmpty || model.selectedDeviceID.isEmpty {
                        Text("To find the USB target at launch, first choose the tool and iPhone on the Connection screen.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if startup.loginItemStatus == .requiresApproval {
                        Text("To launch at login, allow IMove in macOS System Settings → General → Login Items.")
                            .font(.system(size: 12)).foregroundStyle(.yellow)
                    }
                    Button("Refresh login item status") { startup.refreshLoginItemStatus() }
                        .buttonStyle(.borderless)
                    if let error = startup.errorMessage {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    }
                }
            }
            panel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Phone connection").font(.system(size: 15, weight: .semibold))
                    Text("First choose the iPhone on the Connection screen. Then install Tailscale on the Mac and your phone and create an HTTPS address only you can reach. The guide has the steps.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Button("Open setup guide", action: openGuide).buttonStyle(.borderless)
                }
            }
        }
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Every step, visible.").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("The last 50 actions in this session. The log is cleared when the app quits.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if model.activities.isEmpty {
                panel {
                    VStack(spacing: 14) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 32)).foregroundStyle(.secondary)
                        Text("No activity yet").font(.system(size: 17, weight: .medium))
                        Text("Send your first test location and the result will show up here.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Choose location") { page = .location }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity).padding(.vertical, 35)
                }
            } else {
                panel {
                    VStack(spacing: 0) {
                        ForEach(Array(model.activities.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider().padding(.vertical, 15) }
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: entry.symbol).font(.system(size: 17))
                                    .foregroundStyle(entry.isError ? .red : brand).frame(width: 23)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.title).font(.system(size: 13, weight: .medium))
                                    Text(entry.detail).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer(minLength: 10)
                                Text(entry.time, style: .time).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func coordinateField(_ title: String, hint: String, value: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium))
            TextField(hint, text: value)
                .textFieldStyle(.plain).font(.system(size: 20, design: .monospaced))
                .padding(13)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.10)))
                .accessibilityLabel(title).accessibilityIdentifier(id)
        }.frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 10) {
                Text(message).font(.system(size: 12)).textSelection(.enabled)
                if model.errorDetails != nil {
                    Button("Error details") { navigation.showingErrorDetails = true }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("show-error-details")
                }
            }
            Spacer(minLength: 0)
            Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss error message")
        }
        .padding(15).background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
    }

    private var errorDetailsSheet: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("Error details").font(.system(size: 21, weight: .semibold))
                Spacer()
                Button("Close") { navigation.showingErrorDetails = false }
            }
            Text("Below is the end of the output; the real cause is usually in the last lines.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                Text(String((model.errorDetails ?? "").suffix(8000)))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Button("Copy all details") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(model.errorDetails ?? "", forType: .string)
                }
                Spacer()
            }
        }
        .padding(25)
        .frame(width: 740, height: 520)
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(brand.opacity(0.12)))
    }
}
