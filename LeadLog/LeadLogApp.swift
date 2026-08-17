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
        configureTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color.lgAccentText)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .modelContainer(container)
    }

    private func configureTabBarAppearance() {
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

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Color.lgBackground)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(Color.lgText)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.lgText)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
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
        .environmentObject(router)
    }
}
