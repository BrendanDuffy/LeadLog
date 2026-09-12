import SwiftUI
import SwiftData
import Combine

@main
struct LeadLogApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([
            Firearm.self,
            LogEntry.self,
            AmmoEntry.self,
            ServiceRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        #if DEBUG
        DemoSeedData.seedIfRequested(in: container)
        #endif
        LgAppearance.configureTabAndNavBars()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .lgDismissKeyboardOnOutsideTap()
        }
        .modelContainer(container)
    }
}

// MARK: - UIAppearance styling
// Tab/nav bar chrome is styled via UIKit's appearance-proxy system, not
// SwiftUI state. That proxy only affects bars created *after* it's set, so
// an accent-color change must both re-apply it and force the tab bar to be
// recreated (`ContentView` does the latter via `.id(accentRefreshToken)` on
// the whole `TabView` — mutating an already-on-screen bar directly turned
// out not to repaint reliably here, so a full remount is what actually
// works, the same path a cold launch already takes).

enum LgAppearance {
    static func configureTabAndNavBars() {
        UITabBar.appearance().standardAppearance = makeTabBarAppearance()
        UITabBar.appearance().scrollEdgeAppearance = makeTabBarAppearance()

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Color.lgBackground)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(Color.lgText)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.lgText)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }

    static func makeTabBarAppearance() -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.lgTabBar)
        appearance.shadowColor = UIColor(Color.lgBorder)

        let unselected = UIColor(Color.lgTextTertiary)
        let selected = UIColor(Color.lgAccentText)
        for itemAppearance in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            itemAppearance.normal.iconColor = unselected
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: unselected, .font: UIFont.systemFont(ofSize: 11, weight: .semibold)]
            itemAppearance.selected.iconColor = selected
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: selected, .font: UIFont.systemFont(ofSize: 11, weight: .semibold)]
        }
        return appearance
    }
}

// MARK: - Tab routing
// Lets a view on one tab (e.g. an empty-state CTA) switch the active tab.

enum AppTab: Hashable {
    case log, inventory, history, settings
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .log
}

// MARK: - Root Tab View

struct ContentView: View {
    @StateObject private var router = AppRouter()
    // Bumped whenever the user picks a new accent color or font in Settings.
    // Applied as an `.id()` on the whole `TabView` (not just its tab content)
    // so the tab bar chrome — styled via a UIAppearance proxy, not SwiftUI
    // state — gets fully recreated too and picks up the freshly-reconfigured
    // proxy. Mutating an already-on-screen `UITabBar` directly didn't repaint
    // reliably here; a full remount takes the same path a cold launch
    // already takes, which does work. Safe to reset every tab's local state
    // this way now that every preference is picked with an instant tap, not
    // a modal drag.
    @State private var themeRefreshToken = UUID()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            LogSessionView()
                .tabItem {
                    Label("Log", systemImage: "scope")
                }
                .tag(AppTab.log)
            InventoryView()
                .tabItem {
                    Label("Inventory", systemImage: "shippingbox")
                }
                .tag(AppTab.inventory)
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(AppTab.history)
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.vertical.3")
                }
                .tag(AppTab.settings)
        }
        .id(themeRefreshToken)
        .tint(Color.lgAccentText)
        .onChange(of: router.selectedTab) { _, _ in haptic(.light) }
        .environmentObject(router)
        .onReceive(NotificationCenter.default.publisher(for: LgThemePreference.changedNotification)) { _ in
            LgAppearance.configureTabAndNavBars()
            themeRefreshToken = UUID()
        }
    }
}
