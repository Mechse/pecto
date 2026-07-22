import SwiftUI
import PectoKit
import UserNotifications

struct GeneralSettingsView: View {
    let model: AppModel
    @State private var notificationsAuthorized: Bool?

    var body: some View {
        Form {
            Section {
                ModelPickerView(
                    title: "Default model",
                    defaultOptionLabel: "Built-in (\(ProviderCatalog.defaultModelRef.qualified))",
                    appleAvailable: model.appleAvailability.isAvailable,
                    selection: defaultModelBinding
                )
            } footer: {
                Text("Used by tasks that don't pick their own model. Each task can override it in its configuration.")
            }

            Section("Shortcuts") {
                Text("Give any task its own shortcut in its configuration — click Record and press the keys you want. It works system-wide: copy some text anywhere, press the shortcut, paste the result.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Running indicator") {
                Toggle(
                    "Show a pill at the top of the screen while a task runs",
                    isOn: Binding(
                        get: { model.settings.showRunningIndicator },
                        set: { model.settings.setShowRunningIndicator($0) }
                    )
                )
                Text("On MacBooks with a notch it hugs the notch; elsewhere it floats below the menu bar. It flashes the result when a run finishes.")
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
        .navigationTitle("General")
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAuthorized = settings.authorizationStatus == .authorized
        }
    }

    private var defaultModelBinding: Binding<String?> {
        Binding(
            get: { model.settings.defaultModel },
            set: { model.settings.setDefaultModel($0) }
        )
    }
}
