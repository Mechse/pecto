import SwiftUI

/// The full-window Settings screen: its own sidebar of sections, with a Back
/// button returning to the task UI. Replaces the old separate Settings window.
struct SettingsRootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: sectionBinding) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.closeSettings()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .help("Back to your tasks (Esc)")
                }
            }
        } detail: {
            switch currentSection {
            case .general:
                GeneralSettingsView(model: model)
            case .apiKeys:
                APIKeysSettingsView(model: model)
            case .workspace:
                WorkspaceSettingsView(model: model)
            }
        }
        .onExitCommand {
            model.closeSettings()
        }
    }

    private var currentSection: SettingsSection {
        if case .settings(let section) = model.mainRoute {
            return section
        }
        return .general
    }

    private var sectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { currentSection },
            set: { if let section = $0 { model.mainRoute = .settings(section) } }
        )
    }
}
