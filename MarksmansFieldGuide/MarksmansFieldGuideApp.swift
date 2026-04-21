import SwiftUI
import SwiftData

@main
struct MarksmansFieldGuideApp: App {
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

// MARK: - Root Tab View

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        Group {
            switch selectedTab {
            case 0: LogSessionView()
            case 1: InventoryView()
            case 2: HistoryView()
            case 3: SettingsView()
            default: LogSessionView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WesternTabBar(selectedTab: $selectedTab)
        }
    }
}

// MARK: - Placeholder Tab

struct PlaceholderTab: View {
    let title: String
    let icon: String

    var body: some View {
        ZStack {
            W.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                WesternHeader(title: title)
                GoldDivider()
                Spacer()
                VStack(spacing: 16) {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .opacity(0.4)
                    Text(title)
                        .font(.rye(22))
                        .foregroundStyle(W.muted)
                    Text("Coming soon")
                        .font(.playfairRegular(16))
                        .foregroundStyle(W.muted.opacity(0.6))
                }
                Spacer()
            }
        }
    }
}
