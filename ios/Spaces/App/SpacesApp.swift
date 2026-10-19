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
        case lists = "Lists"
        case search = "Search"
        case new = "New"
        case notes = "Notes"
        case settings = "Profile"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .lists: return "list.bullet"
            case .search: return "magnifyingglass"
            case .new: return "square.and.pencil"
            case .notes: return "doc.text"
            case .settings: return "person.crop.circle"
            }
        }
    }

    @Environment(AppSettings.self) private var settings
    @State private var selection: Tab = .lists
    @State private var didCheckInitialAuth = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            Group {
                switch selection {
                case .lists:
                    ListsView()
                case .search:
                    SearchView()
                case .new:
                    CaptureView()
                case .notes:
                    NotesListView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingDock(selection: $selection)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
        }
        .background(Theme.background.ignoresSafeArea())
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

/// Futuristic Floating Navigation Dock capsule matching the 2026/2027 design specification.
private struct FloatingDock: View {
    @Binding var selection: RootView.Tab
    @Namespace private var dockNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RootView.Tab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundStyle(isSelected ? Theme.inkDark : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(Theme.activeDockGradient)
                                .shadow(color: Theme.apricot.opacity(0.35), radius: 8, y: 2)
                                .matchedGeometryEffect(id: "activeTab", in: dockNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            ZStack {
                Capsule(style: .continuous)
                    .fill(Theme.dock.opacity(0.95))
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.25))
            }
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.border.opacity(0.95), Theme.divider.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
    }
}
