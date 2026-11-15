import SwiftUI

struct RoutesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingEditor = false
    @State private var pendingDelete: SavedRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    Text("Routes").font(.title2.bold())
                    Text("Start routes saved on the Mac from here, or create a new one on the map.")
                        .foregroundColor(IMoveTheme.quiet)
                    ActionButton(title: "Create new route", icon: "point.topleft.down.curvedto.point.bottomright.up") {
                        showingEditor = true
                    }
                    .disabled(store.connection == nil)
                }
                if let status = store.status, !status.routeID.isEmpty {
                    Card {
                        Text("Running route").font(.caption.weight(.bold)).foregroundColor(IMoveTheme.mint)
                        Text(status.routeName).font(.title3.bold())
                        ProgressView(value: status.routeProgress).tint(IMoveTheme.mint)
                        Text("Segment \(status.routeSegmentIndex) / \(status.routeSegmentCount) · \(Int(status.routeProgress * 100))%")
                            .font(.caption).foregroundColor(IMoveTheme.quiet)
                        ActionButton(title: "Stop route", icon: "stop.fill", secondary: true) {
                            Task { _ = await store.perform { try await $0.stopRoute() } }
                        }
                    }
                }
                ForEach(store.routes) { route in
                    Card {
                        HStack {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .foregroundColor(IMoveTheme.mint)
                            Text(route.name).font(.headline)
                        }
                        Text("\(route.points.count) stops · \(route.totalDurationSeconds / 60) min \(route.totalDurationSeconds % 60) s")
                            .font(.caption).foregroundColor(IMoveTheme.quiet)
                        HStack {
                            ActionButton(title: "Start", icon: "play.fill") {
                                Task { _ = await store.perform { try await $0.startRoute(route.id) } }
                            }
                            Button(role: .destructive) { pendingDelete = route } label: {
                                Image(systemName: "trash").frame(width: 44, height: 44)
                            }
                        }
                    }
                }
                if store.routes.isEmpty {
                    Card { Text("No saved routes yet.").foregroundColor(IMoveTheme.quiet) }
                }
                Text(store.message).font(.caption).foregroundColor(IMoveTheme.quiet)
            }
            .padding().frame(maxWidth: 850).frame(maxWidth: .infinity)
        }
        .navigationTitle("Routes")
        .imovePage()
        .task { await store.refreshAll() }
        .sheet(isPresented: $showingEditor) { RouteEditorView() }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "route")?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                if let route = pendingDelete {
                    Button("Delete", role: .destructive) {
                        Task { _ = await store.perform { try await $0.deleteRoute(route.id) } }
                        pendingDelete = nil
                    }
                }
            }
    }
}

struct RouteEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var name = ""
    @State private var points: [Point] = []
    @State private var paths: [[Point]] = []
    @State private var descriptions: [String] = []
    @State private var durations: [Int] = []
    @State private var vias: [[Point]] = []
    @State private var picked: Point?
    @State private var mapMode = 0
    @State private var editLeg = 0
    @State private var timingMode = 0
    @State private var totalMinutes = "10"
    @State private var lineID = "B1"
    @State private var board = 0
    @State private var alight = 1
    @State private var note = "Tap the map to choose the first stop."
    @State private var computing = false

    private var line: TransitLine? { store.transit.first { $0.id == lineID } }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        TextField("Route name", text: $name)
                            .font(.title3.bold())
                            .padding(12).background(IMoveTheme.background, in: RoundedRectangle(cornerRadius: 10))
                        Text("Tap a point on the map to add a stop or a waypoint for the selected segment.")
                            .font(.caption).foregroundColor(IMoveTheme.quiet)
                        MapCanvas(selected: picked, sent: store.lastSentPoint,
                                  routePoints: points, routePaths: paths) { point in picked = point }
                            .frame(height: sizeClass == .regular ? 480 : 340)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        if let picked { Text("Selected: \(picked.label)").font(.caption.monospacedDigit()) }
                        Picker("Map action", selection: $mapMode) {
                            Text("Stop").tag(0)
                            Text("Path waypoint").tag(1)
                        }
                        .pickerStyle(.segmented)
                        ActionButton(title: mapMode == 0 ? "Add stop" : "Add waypoint to path", icon: "plus") {
                            guard let picked else { return }
                            if mapMode == 0 { append(picked) }
                            else { addVia(picked) }
                        }
                        .disabled(picked == nil || (mapMode == 1 && vias.isEmpty))
                    }

                    Card {
                        Text("Path following").font(.title3.bold())
                        if !paths.isEmpty {
                            legPicker
                            Text("\(vias[editLeg].count) waypoint(s). The calculation reshapes the selected segment's path.")
                                .font(.caption).foregroundColor(IMoveTheme.quiet)
                            ActionButton(title: "Calculate walking path", icon: "figure.walk", secondary: true) {
                                Task { await calculateWalkingLeg() }
                            }
                            .disabled(computing)
                            Button("Clear this segment's waypoints") {
                                vias[editLeg] = []
                                paths[editLeg] = [points[editLeg], points[editLeg + 1]]
                                descriptions[editLeg] = "Hand-drawn segment"
                            }
                                .font(.caption)
                        } else {
                            Text("Add two stops first.").foregroundColor(IMoveTheme.quiet)
                        }
                    }

                    Card {
                        Text("Istanbul rail lines").font(.title3.bold())
                        Text("B1 Marmaray · M2 Yenikapı–Hacıosman · M6 Levent–Boğaziçi Hisarüstü")
                            .font(.caption).foregroundColor(IMoveTheme.quiet)
                        if let line {
                            Picker("Line", selection: $lineID) {
                                ForEach(store.transit) { item in Text("\(item.id) · \(item.name)").tag(item.id) }
                            }
                            Picker("Board at", selection: $board) {
                                ForEach(line.stations.indices, id: \.self) { index in
                                    Text(line.stations[index].name).tag(index)
                                }
                            }
                            Picker("Alight at", selection: $alight) {
                                ForEach(line.stations.indices, id: \.self) { index in
                                    Text(line.stations[index].name).tag(index)
                                }
                            }
                            ActionButton(title: "Walk to boarding station", icon: "figure.walk", secondary: true) {
                                Task { await walkToBoard() }
                            }
                            ActionButton(title: "Add line section", icon: "tram.fill") { appendRail() }
                        } else {
                            Text("Loading line data…").foregroundColor(IMoveTheme.quiet)
                        }
                    }

                    Card {
                        Text("Stops and durations").font(.title3.bold())
                        ForEach(points.indices, id: \.self) { index in
                            HStack {
                                Text("\(index + 1)").foregroundColor(IMoveTheme.mint)
                                Text(points[index].label).font(.caption.monospacedDigit())
                                Spacer()
                                if index == points.count - 1 {
                                    Button { removeLast() } label: { Image(systemName: "minus.circle") }
                                }
                            }
                            if index < durations.count {
                                Text(descriptions[index]).font(.caption).foregroundColor(IMoveTheme.quiet)
                                if timingMode == 1 {
                                    HStack {
                                        Text("Duration")
                                        TextField("dk", text: minuteBinding(index))
                                            .keyboardType(.numberPad).frame(width: 52)
                                        Text("min")
                                        TextField("sn", text: secondBinding(index))
                                            .keyboardType(.numberPad).frame(width: 52)
                                        Text("s")
                                    }
                                    .font(.caption)
                                }
                            }
                            Divider()
                        }
                        Picker("Timing", selection: $timingMode) {
                            Text("Split total time").tag(0)
                            Text("Custom per segment").tag(1)
                        }
                        .pickerStyle(.segmented)
                        if timingMode == 0 {
                            HStack {
                                Text("Total minutes")
                                TextField("10", text: $totalMinutes)
                                    .keyboardType(.numberPad).frame(width: 75)
                            }
                        }
                    }

                    Card {
                        Text(note).font(.caption).foregroundColor(IMoveTheme.quiet)
                        ActionButton(title: "Save route", icon: "checkmark.circle.fill") {
                            Task { await save() }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || points.count < 2)
                    }
                }
                .padding().frame(maxWidth: sizeClass == .regular ? 1100 : 850).frame(maxWidth: .infinity)
            }
            .navigationTitle("New route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .imovePage()
        }
        .navigationViewStyle(.stack)
        .task { await store.loadTransit() }
        .onChange(of: lineID) { _ in board = 0; alight = 1 }
    }

    private var legPicker: some View {
        Picker("Segment to edit", selection: $editLeg) {
            ForEach(paths.indices, id: \.self) { index in
                Text("\(index + 1) → \(index + 2) · \(descriptions[index])").tag(index)
            }
        }
    }

    private func append(_ point: Point, path: [Point]? = nil,
                        description: String = "Hand-drawn segment", seconds: Int = 300) {
        if let previous = points.last {
            paths.append(path ?? [previous, point])
            descriptions.append(description)
            durations.append(seconds)
            vias.append([])
            editLeg = paths.count - 1
        }
        points.append(point)
        note = "Stop \(points.count) added."
    }

    private func removeLast() {
        guard !points.isEmpty else { return }
        points.removeLast()
        if !paths.isEmpty {
            paths.removeLast(); descriptions.removeLast(); durations.removeLast(); vias.removeLast()
            editLeg = max(0, paths.count - 1)
        }
    }

    private func addVia(_ point: Point) {
        guard paths.indices.contains(editLeg) else { return }
        vias[editLeg].append(point)
        paths[editLeg] = [points[editLeg]] + vias[editLeg] + [points[editLeg + 1]]
        descriptions[editLeg] = "Hand-edited path"
        note = "Waypoint added to the path. You can calculate the walking path now."
    }

    private func calculateWalkingLeg() async {
        guard paths.indices.contains(editLeg), let api = store.connection.map({ IMoveAPI(connection: $0) }) else { return }
        computing = true
        defer { computing = false }
        let index = editLeg
        let waypoints = [points[index]] + vias[index] + [points[index + 1]]
        guard waypoints.count <= 10 else { note = "A walking calculation can have at most 8 waypoints."; return }
        do {
            let (path, estimated) = try await api.walkingPath(waypoints)
            guard paths.indices.contains(index), points[index] == waypoints.first,
                  points[index + 1] == waypoints.last else { return }
            paths[index] = path
            descriptions[index] = "Walk · follows streets"
            durations[index] = min(86_400, max(1, estimated))
            note = "Walking route and estimated duration added."
        } catch { note = error.localizedDescription }
    }

    private func walkToBoard() async {
        guard let line, line.stations.indices.contains(board),
              let api = store.connection.map({ IMoveAPI(connection: $0) }) else { return }
        let destination = line.stations[board].point
        guard let start = points.last else { append(destination); return }
        if start == destination { note = "The route is already at this station."; return }
        computing = true
        defer { computing = false }
        do {
            let (path, estimated) = try await api.walkingPath([start, destination])
            guard points.last == start else { return }
            append(destination, path: path, description: "Walk · \(line.stations[board].name)",
                   seconds: min(86_400, max(1, estimated)))
        } catch { note = error.localizedDescription }
    }

    private func appendRail() {
        guard let line, line.stations.indices.contains(board), line.stations.indices.contains(alight),
              board != alight else { note = "Choose different boarding and alighting stations."; return }
        let origin = line.stations[board].point
        if let previous = points.last, previous != origin {
            let meters = hypot((previous.latitude - origin.latitude) * 111_000,
                               (previous.longitude - origin.longitude) * 111_000 * cos(origin.latitude * .pi / 180))
            guard meters <= 400 else { note = "The boarding station is far away. Add the walking segment first."; return }
            append(origin, description: "Transfer · short walk (approximate)",
                   seconds: max(60, Int(meters / 1.2)))
        } else if points.isEmpty { append(origin) }
        let step = board < alight ? 1 : -1
        for index in stride(from: board, to: alight, by: step) {
            let next = index + step
            let source = line.stations[min(index, next)]
            var path = (source.pathToNext ?? []).compactMap { pair -> Point? in
                guard pair.count == 2 else { return nil }
                return Point(pair[0], pair[1])
            }
            guard path.count >= 2 else { note = "Line path missing."; return }
            if step < 0 { path.reverse() }
            let start = line.stations[index].point
            let end = line.stations[next].point
            path[0] = start
            path[path.count - 1] = end
            append(end, path: path,
                   description: "\(line.id) · \(line.stations[index].name) → \(line.stations[next].name)",
                   seconds: line.id == "B1" ? 150 : 120)
        }
        note = "\(line.id): \(abs(alight - board)) stations added. Review the durations."
    }

    private func minuteBinding(_ index: Int) -> Binding<String> {
        Binding(get: { String(durations[index] / 60) }, set: { value in
            if let minutes = Int(value), (0...1440).contains(minutes) {
                durations[index] = min(86_400, minutes * 60 + durations[index] % 60)
            }
        })
    }

    private func secondBinding(_ index: Int) -> Binding<String> {
        Binding(get: { String(durations[index] % 60) }, set: { value in
            if let seconds = Int(value), (0...59).contains(seconds) {
                durations[index] = durations[index] / 60 * 60 + seconds
            }
        })
    }

    private func save() async {
        let selectedDurations: [Int]
        if timingMode == 0 {
            guard let minutes = Int(totalMinutes), minutes > 0, minutes <= 1440,
                  let distributed = IMoveValidation.equalDurations(totalSeconds: minutes * 60,
                                                                   segments: points.count - 1) else {
                note = "The total duration must give each segment at least 1 second."
                return
            }
            selectedDurations = distributed
        } else {
            guard durations.allSatisfy({ (1...86_400).contains($0) }) else {
                note = "Each segment must last between 1 second and 24 hours."
                return
            }
            selectedDurations = durations
        }
        let saved = await store.perform { api in
            try await api.saveRoute(name: name, points: points, durations: selectedDurations,
                                    paths: paths, descriptions: descriptions,
                                    timingMode: timingMode == 0 ? "equal" : "custom")
        }
        if saved { dismiss() }
        else { note = store.message }
    }
}
