import SwiftUI

enum IMoveTheme {
    static let background = Color(red: 0.045, green: 0.073, blue: 0.065)
    static let surface = Color(red: 0.085, green: 0.13, blue: 0.11)
    static let mint = Color(red: 0.32, green: 0.88, blue: 0.56)
    static let quiet = Color(red: 0.61, green: 0.70, blue: 0.65)
}

@main
struct IMoveMobileApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(IMoveTheme.mint)
                .onChange(of: scenePhase) { phase in
                    if phase == .active { Task { await store.refreshAll() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView {
            NavigationView { DashboardView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Location", systemImage: "location.fill") }
            NavigationView { PlacesView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Places", systemImage: "bookmark.fill") }
            NavigationView { RoutesView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
            NavigationView { SettingsView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Connection", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .background(IMoveTheme.background)
        .overlay(alignment: .top) {
            if store.working { ProgressView().padding(8).background(.ultraThinMaterial).clipShape(Capsule()) }
        }
    }
}

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IMoveTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(IMoveTheme.mint.opacity(0.14)))
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    var secondary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .foregroundColor(secondary ? IMoveTheme.mint : IMoveTheme.background)
        .background(secondary ? IMoveTheme.mint.opacity(0.12) : IMoveTheme.mint,
                    in: RoundedRectangle(cornerRadius: 13))
    }
}

extension View {
    func imovePage() -> some View {
        self.background(IMoveTheme.background.ignoresSafeArea())
    }
}
