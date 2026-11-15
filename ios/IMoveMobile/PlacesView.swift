import SwiftUI

struct PlacesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var name = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var pendingDelete: Place?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    Text("New place").font(.title3.bold())
                    TextField("Place name", text: $name)
                        .textInputAutocapitalization(.words)
                        .padding(12).background(IMoveTheme.background, in: RoundedRectangle(cornerRadius: 10))
                    HStack {
                        TextField("Latitude", text: $latitude).keyboardType(.decimalPad)
                        TextField("Longitude", text: $longitude).keyboardType(.decimalPad)
                    }
                    .padding(12).background(IMoveTheme.background, in: RoundedRectangle(cornerRadius: 10))
                    if let selected = store.selectedPoint {
                        Button("Use the point picked on the map: \(selected.label)") {
                            latitude = String(selected.latitude)
                            longitude = String(selected.longitude)
                        }
                        .font(.caption)
                    }
                    ActionButton(title: "Save place", icon: "plus") {
                        guard let point = IMoveValidation.point(latitude: latitude, longitude: longitude) else { return }
                        Task {
                            let saved = await store.perform { try await $0.addPlace(name: name, point: point) }
                            if saved { name = "" }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              IMoveValidation.point(latitude: latitude, longitude: longitude) == nil || store.connection == nil)
                }

                Card {
                    Text("Saved places").font(.title3.bold())
                    if store.places.isEmpty {
                        Text("No saved places yet.").foregroundColor(IMoveTheme.quiet)
                    }
                    ForEach(store.places) { place in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(place.name).font(.headline)
                            Text(place.point.label).font(.caption.monospacedDigit()).foregroundColor(IMoveTheme.quiet)
                            HStack {
                                Button("Pick on map") { store.selectedPoint = place.point }
                                Spacer()
                                Button("Send") { Task { _ = await store.send(place.point) } }
                                Spacer()
                                Button(role: .destructive) { pendingDelete = place } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
            .padding()
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Saved places")
        .imovePage()
        .task { await store.refreshAll() }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "place")?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                if let place = pendingDelete {
                    Button("Delete", role: .destructive) {
                        Task { _ = await store.perform { try await $0.deletePlace(place.id) } }
                        pendingDelete = nil
                    }
                }
            }
    }
}
