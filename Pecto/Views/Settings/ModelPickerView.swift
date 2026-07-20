import SwiftUI
import PectoKit

/// Model choices grouped by provider — shared by the per-task config and the
/// global default-model setting. Writes are always provider-qualified; a
/// current value outside the curated lists (bare legacy IDs, free-form
/// strings) is kept selectable verbatim so opening the picker never silently
/// resets it.
struct ModelPickerView: View {
    let title: String
    /// Label for the nil choice, e.g. "Default (anthropic/claude-sonnet-4-5)".
    let defaultOptionLabel: String
    let appleAvailable: Bool
    @Binding var selection: String?

    var body: some View {
        Picker(title, selection: $selection) {
            Text(defaultOptionLabel).tag(nil as String?)
            ForEach(visibleProviders) { info in
                Section(info.displayName) {
                    ForEach(pickerModels(for: info), id: \.self) { model in
                        Text(model).tag(Optional("\(info.id.rawValue)/\(model)"))
                    }
                }
            }
            if let current = selection, !knownTags.contains(current) {
                Section("Custom") {
                    Text(current).tag(Optional(current))
                }
            }
        }
    }

    private var visibleProviders: [ProviderInfo] {
        ProviderCatalog.all.filter { $0.id != .apple || appleAvailable }
    }

    private func pickerModels(for info: ProviderInfo) -> [String] {
        info.selectableModels.contains(info.defaultModel)
            ? info.selectableModels
            : [info.defaultModel] + info.selectableModels
    }

    private var knownTags: Set<String> {
        Set(visibleProviders.flatMap { info in
            pickerModels(for: info).map { "\(info.id.rawValue)/\($0)" }
        })
    }
}
