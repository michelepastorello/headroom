import AppKit
import Carbon.HIToolbox

/// Global shortcuts via Carbon RegisterEventHotKey: work system-wide without
/// accessibility permissions. ⌃⌥H toggles the popover, ⌃⌥J the HUD.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onToggleDashboard: (() -> Void)?
    var onToggleHUD: (() -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    func register() {
        guard hotKeyRefs.isEmpty else { return }

        if handlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(GetApplicationEventTarget(), headroomHotKeyHandler, 1, &eventType, nil, &handlerRef)
        }

        let bindings: [(id: UInt32, key: Int)] = [
            (1, kVK_ANSI_H),   // popover
            (2, kVK_ANSI_J)    // HUD
        ]
        for binding in bindings {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4844_524D), id: binding.id) // "HDRM"
            RegisterEventHotKey(
                UInt32(binding.key),
                UInt32(controlKey | optionKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if let ref {
                hotKeyRefs.append(ref)
            }
        }
    }

    func unregister() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    func trigger(id: UInt32) {
        switch id {
        case 1: onToggleDashboard?()
        case 2: onToggleHUD?()
        default: break
        }
    }
}

/// C callback: cannot capture context, so it reads the hot-key id from the
/// event and reaches the singleton. Carbon delivers application-target
/// events on the main thread.
private let headroomHotKeyHandler: EventHandlerUPP = { _, event, _ in
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
    let id = hotKeyID.id
    Task { @MainActor in
        HotKeyManager.shared.trigger(id: id)
    }
    return noErr
}
