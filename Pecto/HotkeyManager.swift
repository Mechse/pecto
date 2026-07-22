import Carbon.HIToolbox
import Foundation
import PectoKit

/// Registers the user's recorded shortcuts as system-wide hotkeys via Carbon
/// `RegisterEventHotKey`, which works without the Accessibility permission.
@MainActor
final class HotkeyManager {
    private static let signature: OSType = 0x5045_4354 // 'PECT'

    private let onShortcut: (Shortcut) -> Void
    private var eventHandler: EventHandlerRef?
    /// Hotkey id → the shortcut it stands for, so the C callback can resolve
    /// an incoming event back to something meaningful.
    private var registered: [UInt32: (shortcut: Shortcut, ref: EventHotKeyRef)] = [:]
    private var nextID: UInt32 = 1
    /// What `sync` was last asked to register — replayed by `resume`.
    private var desired: Set<Shortcut> = []
    private var isSuspended = false

    init(onShortcut: @escaping (Shortcut) -> Void) {
        self.onShortcut = onShortcut
    }

    /// Registers exactly `shortcuts`, replacing whatever was registered before.
    /// Returns the shortcuts the OS refused — macOS or another app owns them.
    @discardableResult
    func sync(_ shortcuts: Set<Shortcut>) -> Set<Shortcut> {
        installHandlerIfNeeded()
        desired = shortcuts
        guard !isSuspended else { return [] }

        unregisterAll()
        var failed: Set<Shortcut> = []
        for shortcut in shortcuts {
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode),
                Self.carbonModifiers(shortcut.modifiers),
                EventHotKeyID(signature: Self.signature, id: id),
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registered[id] = (shortcut, ref)
            } else {
                failed.insert(shortcut)
            }
        }
        return failed
    }

    /// Releases every hotkey while the recorder captures keystrokes, so
    /// pressing an already-assigned shortcut gets recorded instead of firing
    /// a run. Always paired with `resume()`.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        sync(desired)
    }

    private func unregisterAll() {
        for (_, entry) in registered {
            UnregisterEventHotKey(entry.ref)
        }
        registered.removeAll()
    }

    private static func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
        var mask = 0
        if modifiers.contains(.command) { mask |= cmdKey }
        if modifiers.contains(.option) { mask |= optionKey }
        if modifiers.contains(.control) { mask |= controlKey }
        if modifiers.contains(.shift) { mask |= shiftKey }
        return UInt32(mask)
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // Carbon delivers hotkey events on the main run loop, so hopping back
        // onto the main actor from the C callback is safe and immediate.
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard hotKeyID.signature == HotkeyManager.signature else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                Task { @MainActor in
                    guard let shortcut = manager.registered[id]?.shortcut else { return }
                    manager.onShortcut(shortcut)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    // No deinit cleanup: the manager lives for the whole app lifetime and the
    // OS drops hotkey registrations when the process exits.
}
