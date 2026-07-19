import SwiftUI
import AppKit
import UserNotifications

struct SettingsView: View {
    let model: AppModel
    @State private var apiKeyDraft = ""
    @State private var hasStoredKey = false
    @State private var didJustSave = false
    @State private var notificationsAuthorized: Bool?

    var body: some View {
        Form {
            Section("Anthropic API key") {
                SecureField("sk-ant-…", text: $apiKeyDraft)
                    .onSubmit(saveKey)
                HStack {
                    Button("Save Key", action: saveKey)
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if didJustSave {
                        Label("Saved to your keychain", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text(hasStoredKey ? "A key is stored in your keychain." : "No key yet — runs will fail until you add one.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                if hasStoredKey {
                    Button("Remove Key", role: .destructive) {
                        KeychainService.deleteAPIKey()
                        apiKeyDraft = ""
                        hasStoredKey = false
                        didJustSave = false
                        model.refreshAPIKeyStatus()
                    }
                }
            }

            Section("Workspace") {
                LabeledContent("Folder", value: model.settings.workspacePath)
                Text("Every .md file in this folder is a task.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Change Folder…", action: pickWorkspaceFolder)
            }

            Section("Shortcuts") {
                Text("⌃⌥1 through ⌃⌥9 work system-wide. Assign a task to a slot in the editor, copy some text anywhere, press the shortcut, and paste the result.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                switch notificationsAuthorized {
                case .some(true):
                    Label("Run results are announced as notifications.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                case .some(false):
                    Label(
                        "Notifications are off — allow Pecto in System Settings → Notifications. Run results always show at the bottom of the Pecto window too.",
                        systemImage: "bell.slash"
                    )
                    .foregroundStyle(.secondary)
                case .none:
                    Label("Checking notification status…", systemImage: "bell")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            hasStoredKey = KeychainService.loadAPIKey() != nil
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAuthorized = settings.authorizationStatus == .authorized
        }
    }

    private func saveKey() {
        KeychainService.saveAPIKey(apiKeyDraft)
        hasStoredKey = KeychainService.loadAPIKey() != nil
        didJustSave = hasStoredKey
        apiKeyDraft = ""
        model.refreshAPIKeyStatus()
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
