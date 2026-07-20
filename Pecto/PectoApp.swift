import SwiftUI
import UserNotifications

@main
struct PectoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: model.runner.isRunning ? "wand.and.rays" : "wand.and.stars")
        }

        Window("Pecto", id: "main") {
            MainWindowView(model: model)
        }
        .defaultSize(width: 880, height: 560)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            EditorFontCommands()
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.requestAuthorization()

        // The app is LSUIElement (menu-bar agent), but while an actual window
        // is open it should behave like a normal app: Dock icon and ⌘-tab.
        // Track window comings and goings and flip the activation policy.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                // On willClose the window still reports as visible; recount
                // one runloop tick later, when the close has taken effect.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        Self.syncActivationPolicy()
                    }
                }
            }
        }
    }

    /// Dock icon while any real window (main or Settings) is open; back to a
    /// pure menu-bar agent when the last one closes. Panels (the notch
    /// indicator) and the status-bar window never count.
    private static func syncActivationPolicy() {
        let hasUserWindow = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled) && !(window is NSPanel)
        }
        let desired: NSApplication.ActivationPolicy = hasUserWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != desired else { return }
        NSApp.setActivationPolicy(desired)
        if desired == .regular {
            NSApp.activate()
        }
    }

    // Show banners even while Pecto is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
