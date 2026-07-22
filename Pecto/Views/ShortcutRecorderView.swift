import AppKit
import Carbon.HIToolbox
import PectoKit
import SwiftUI

/// Records a global shortcut for the selected task: click, press the keys you
/// want, done. Runnability is judged on the saved file — that's what a
/// shortcut executes.
struct ShortcutRecorderView: View {
    let model: AppModel
    let task: TaskSummary

    @State private var isRecording = false
    /// Modifiers held right now, for the live "⌃⌥…" preview.
    @State private var liveModifiers: ShortcutModifiers = []
    /// Inline result of the last attempt — never an alert.
    @State private var status: Status?

    private enum Status: Equatable {
        case needsModifier
        case replaced(taskName: String)
        case unavailable
        case cleared

        var text: String {
            switch self {
            case .needsModifier:
                "Add ⌘, ⌃ or ⌥ — a bare key would be swallowed in every app."
            case .replaced(let taskName):
                "Taken over from \(taskName)."
            case .unavailable:
                "macOS or another app already uses that shortcut. Try a different one."
            case .cleared:
                "Shortcut removed."
            }
        }

        var isProblem: Bool {
            self == .needsModifier || self == .unavailable
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Shortcut")
                Spacer()
                recorderButton
                if current != nil, !isRecording {
                    Button {
                        model.clearShortcut(for: task.path)
                        status = .cleared
                    } label: {
                        // Padded past the glyph's own 13pt so the target is
                        // comfortably clickable.
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove this shortcut")
                }
            }
            if let status, isRunnable {
                Text(status.text)
                    .font(.callout)
                    .foregroundStyle(status.isProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
        }
        .disabled(!isRunnable)
        .help(helpText)
        .onChange(of: task.path) {
            isRecording = false
            status = nil
        }
    }

    private var recorderButton: some View {
        Button {
            isRecording.toggle()
            status = nil
        } label: {
            Text(buttonLabel)
                .font(.body.monospaced())
                .frame(minWidth: 120)
        }
        .background(
            KeyCaptureView(
                isRecording: $isRecording,
                liveModifiers: $liveModifiers,
                onCommit: commit,
                onClear: {
                    model.clearShortcut(for: task.path)
                    status = .cleared
                },
                onSuspendHotkeys: model.suspendHotkeys,
                onResumeHotkeys: model.resumeHotkeys
            )
            .frame(width: 0, height: 0)
        )
    }

    private var buttonLabel: String {
        if isRecording {
            return liveModifiers.isEmpty ? "Type a shortcut…" : liveModifiers.display + "…"
        }
        return current?.display ?? "Record Shortcut"
    }

    private var current: Shortcut? {
        model.settings.shortcut(for: task.path)
    }

    private func commit(_ shortcut: Shortcut) {
        guard shortcut.hasRequiredModifier else {
            status = .needsModifier
            return
        }
        isRecording = false
        switch model.setShortcut(shortcut, for: task.path) {
        case .assigned: status = nil
        case .replaced(let taskName): status = .replaced(taskName: taskName)
        case .unavailable: status = .unavailable
        }
    }

    // MARK: - Runnability (only clipboard-shaped tasks can have a shortcut)

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
        return "Click, then press the keys that should run this task on your clipboard. Esc cancels, ⌫ clears."
    }
}

// MARK: - Key capture

/// Zero-sized AppKit view that owns first responder while recording. AppKit is
/// the only way to see raw key codes and swallow ⌘-combos before the menus.
private struct KeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var liveModifiers: ShortcutModifiers
    let onCommit: (Shortcut) -> Void
    let onClear: () -> Void
    let onSuspendHotkeys: () -> Void
    let onResumeHotkeys: () -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        wire(view)
        return view
    }

    func updateNSView(_ view: CaptureNSView, context: Context) {
        wire(view)

        guard view.isRecording != isRecording else { return }
        view.isRecording = isRecording
        if isRecording {
            onSuspendHotkeys()
            liveModifiers = []
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        } else {
            onResumeHotkeys()
            if view.window?.firstResponder === view {
                view.window?.makeFirstResponder(nil)
            }
        }
    }

    static func dismantleNSView(_ view: CaptureNSView, coordinator: ()) {
        // A view torn down mid-recording must not leave hotkeys suspended.
        if view.isRecording {
            view.isRecording = false
            view.onResumeHotkeys?()
        }
    }

    private func wire(_ view: CaptureNSView) {
        view.onCommit = onCommit
        view.onClear = onClear
        view.onCancel = { isRecording = false }
        view.onModifiersChanged = { liveModifiers = $0 }
        view.onResumeHotkeys = onResumeHotkeys
    }
}

private final class CaptureNSView: NSView {
    var isRecording = false
    var onCommit: ((Shortcut) -> Void)?
    var onClear: (() -> Void)?
    var onCancel: (() -> Void)?
    var onModifiersChanged: ((ShortcutModifiers) -> Void)?
    /// Re-arms the global hotkeys; also used if the view dies mid-recording.
    var onResumeHotkeys: (() -> Void)?

    override var acceptsFirstResponder: Bool { isRecording }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        onModifiersChanged?(Self.modifiers(from: event))
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handle(event)
    }

    /// ⌘-combos never reach `keyDown` — the menu bar gets first crack at them,
    /// so recording has to intercept here and report the event consumed.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        handle(event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            onCancel?()
        }
        return super.resignFirstResponder()
    }

    private func handle(_ event: NSEvent) {
        let modifiers = Self.modifiers(from: event)
        let code = Int(event.keyCode)
        let isDelete = code == kVK_Delete || code == kVK_ForwardDelete

        if code == kVK_Escape {
            isRecording = false
            onCancel?()
        } else if isDelete, modifiers.isEmpty {
            isRecording = false
            onCancel?()
            onClear?()
        } else {
            onCommit?(Shortcut(keyCode: event.keyCode, modifiers: modifiers))
        }
    }

    private static func modifiers(from event: NSEvent) -> ShortcutModifiers {
        var result: ShortcutModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}
