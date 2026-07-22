import SwiftUI

struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let assignments = model.settings.shortcuts
            .map { (path: $0.key, shortcut: $0.value) }
            .sorted { displayName(for: $0.path) < displayName(for: $1.path) }

        if assignments.isEmpty {
            Text("No shortcuts assigned yet")
        } else {
            ForEach(assignments, id: \.path) { path, shortcut in
                let running = model.runner.runningPaths.contains(path)
                Button {
                    model.runner.run(path: path)
                } label: {
                    Text("\(shortcut.display)   \(displayName(for: path))\(running ? "  — running…" : "")")
                }
                .disabled(running)
            }
        }

        Divider()

        Button("Open Pecto") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Settings…") {
            model.openSettings()
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
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
