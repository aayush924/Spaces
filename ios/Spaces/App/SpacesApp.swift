import SwiftUI

@main
struct SpacesApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    enum Tab: String, CaseIterable, Hashable, Identifiable {
        case todos = "Todos"
        case lists = "Lists"
        case new = "New"
        case notes = "Notes"
        case settings = "Profile"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .todos: return "checklist"
            case .lists: return "list.bullet"
            case .new: return "square.and.pencil"
            case .notes: return "doc.text"
            case .settings: return "person.crop.circle"
            }
        }
    }

    @Environment(AppSettings.self) private var settings
    @State private var selection: Tab = .todos
    @State private var didCheckInitialAuth = false

    var body: some View {
        TabView(selection: $selection) {
            TodosView()
                .tabItem {
                    Label(Tab.todos.rawValue, systemImage: Tab.todos.icon)
                }
                .tag(Tab.todos)

            ListsView()
                .tabItem {
                    Label(Tab.lists.rawValue, systemImage: Tab.lists.icon)
                }
                .tag(Tab.lists)

            CaptureView()
                .tabItem {
                    Label(Tab.new.rawValue, systemImage: Tab.new.icon)
                }
                .tag(Tab.new)

            NotesListView()
                .tabItem {
                    Label(Tab.notes.rawValue, systemImage: Tab.notes.icon)
                }
                .tag(Tab.notes)

            SettingsView()
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
        .tint(Theme.apricot)
        .onAppear {
            guard !didCheckInitialAuth else { return }
            didCheckInitialAuth = true
            if !settings.isConfigured {
                selection = .settings
            }
        }
        .onChange(of: settings.isConfigured) { _, isLoggedIn in
            if !isLoggedIn {
                selection = .settings
            }
        }
    }
}
