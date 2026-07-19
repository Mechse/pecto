import SwiftUI
import PectoKit

/// Assigns the selected task to one of the ⌃⌥1–9 shortcut slots.
/// Runnability is judged on the saved file — that's what a shortcut executes.
struct SlotPickerView: View {
    let model: AppModel
    let task: TaskSummary

    var body: some View {
        Picker("Shortcut", selection: slotBinding) {
            Text("No Shortcut").tag(nil as Int?)
            ForEach(1...SettingsStore.slotCount, id: \.self) { slot in
                Text(label(for: slot)).tag(Optional(slot))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(!isRunnable)
        .help(helpText)
    }

    private var isRunnable: Bool {
        task.error == nil && (task.placeholders.isEmpty || task.placeholders == ["clipboard"])
    }

    private var helpText: String {
        if let error = task.error {
            return error
        }
        if !isRunnable {
            let foreign = task.placeholders.filter { $0 != "clipboard" }
                .map { "{{\($0)}}" }
                .joined(separator: ", ")
            return "This task asks for \(foreign), but a shortcut can only fill {{clipboard}}. Rewrite it to use {{clipboard}} as its single input."
        }
        return "Pick a global shortcut that runs this task on your clipboard."
    }

    private var slotBinding: Binding<Int?> {
        Binding(
            get: { model.settings.slot(for: task.path) },
            set: { model.settings.assign(task.path, to: $0) }
        )
    }

    private func label(for slot: Int) -> String {
        if let occupant = model.settings.assignment(for: slot), occupant != task.path {
            return "⌃⌥\(slot) — takes over from \(String(occupant.dropLast(3)))"
        }
        return "⌃⌥\(slot)"
    }
}
