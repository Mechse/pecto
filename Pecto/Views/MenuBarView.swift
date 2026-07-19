import SwiftUI

struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let assignments = model.settings.slotAssignments.sorted { $0.key < $1.key }

        if assignments.isEmpty {
            Text("No shortcuts assigned yet")
        } else {
            ForEach(assignments, id: \.key) { slot, path in
                let running = model.runner.runningPaths.contains(path)
                Button {
                    model.runner.fire(slot: slot)
                } label: {
                    Text("⌃⌥\(slot)   \(displayName(for: path))\(running ? "  — running…" : "")")
                }
                .disabled(running)
            }
        }

        Divider()

        Button("Open Pecto") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Pecto") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func displayName(for path: String) -> String {
        model.tasks.first { $0.path == path }?.name ?? path
    }
}
