import Carbon.HIToolbox
import Foundation

/// Registers ⌃⌥1–⌃⌥9 as system-wide hotkeys via Carbon `RegisterEventHotKey`,
/// which works without the Accessibility permission.
@MainActor
final class HotkeyManager {
    /// kVK_ANSI_1 … kVK_ANSI_9 — deliberately non-sequential.
    private static let slotKeyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    private static let signature: OSType = 0x5045_4354 // 'PECT'

    private let onSlot: (Int) -> Void
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    init(onSlot: @escaping (Int) -> Void) {
        self.onSlot = onSlot
    }

    func register() {
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
                let slot = Int(hotKeyID.id)
                Task { @MainActor in
                    manager.onSlot(slot)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        for (index, keyCode) in Self.slotKeyCodes.enumerated() {
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            RegisterEventHotKey(
                keyCode,
                UInt32(controlKey | optionKey),
                id,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if let ref {
                hotKeyRefs.append(ref)
            }
        }
    }

    // No deinit cleanup: the manager lives for the whole app lifetime and the
    // OS drops hotkey registrations when the process exits.
}
