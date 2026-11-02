import Carbon
import Foundation

/// System-wide shortcut through Carbon's RegisterEventHotKey: no Accessibility permission needed,
/// and the keystroke is swallowed so the app in front never sees it.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private var ref: EventHotKeyRef?
    private let id: UInt32

    init(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        id = UInt32(HotKey.handlers.count + 1)
        HotKey.handlers[id] = handler
        HotKey.installHandler()
        let hkID = EventHotKeyID(signature: OSType(0x5A4F4352), id: id)   // 'ZOCR'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { HotKey.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
