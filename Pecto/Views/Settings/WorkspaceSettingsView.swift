import SwiftUI
import AppKit

struct WorkspaceSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder", value: model.settings.workspacePath)
                Text("Every .md file in this folder is a task.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Change Folder…", action: pickWorkspaceFolder)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Workspace")
    }

    private func pickWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = model.settings.workspaceURL
        panel.prompt = "Use This Folder"
        if panel.runModal() == .OK, let url = panel.url {
            model.changeWorkspace(to: url.path)
        }
    }
}
