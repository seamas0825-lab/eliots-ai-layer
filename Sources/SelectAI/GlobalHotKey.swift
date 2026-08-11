import AppKit
import Carbon.HIToolbox

struct ClipboardShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiersRawValue: UInt
    let keyLabel: String

    static let defaultValue = ClipboardShortcut(
        keyCode: 9,
        modifiersRawValue: NSEvent.ModifierFlags([.command, .option]).rawValue,
        keyLabel: "V"
    )

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue)
            .intersection(.deviceIndependentFlagsMask)
    }

    var displayString: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        return value + keyLabel
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    static func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "空格"
        case 51: return "⌫"
        case 53: return "Esc"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "⌦"
        case 119: return "End"
        case 121: return "Page Down"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let value = event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            return value.isEmpty ? "键 \(event.keyCode)" : value
        }
    }
}

private let clipboardHotKeyEventHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return noErr }
    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { hotKey.fire() }
    return noErr
}

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            clipboardHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    func update(shortcut: ClipboardShortcut) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        let identifier = EventHotKeyID(signature: 0x53414943, id: 1) // "SAIC"
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    fileprivate func fire() { handler() }
}

final class ShortcutRecorderButton: NSButton {
    var onShortcutChanged: ((ClipboardShortcut) -> Void)?
    private(set) var shortcut: ClipboardShortcut = .defaultValue
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = shortcut.displayString
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        target = self
        action = #selector(beginRecording)
        toolTip = "点击后按下新的快捷键"
        setAccessibilityLabel("剪贴板呼出快捷键")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    func setShortcut(_ value: ClipboardShortcut) {
        shortcut = value
        if !isRecording { title = value.displayString }
    }

    @objc private func beginRecording() {
        isRecording = true
        title = "请按快捷键…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            isRecording = false
            title = shortcut.displayString
            window?.makeFirstResponder(nil)
            return
        }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        let value = ClipboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifiersRawValue: modifiers.rawValue,
            keyLabel: ClipboardShortcut.keyLabel(for: event)
        )
        shortcut = value
        isRecording = false
        title = value.displayString
        onShortcutChanged?(value)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if isRecording {
            isRecording = false
            title = shortcut.displayString
        }
        return result
    }
}
