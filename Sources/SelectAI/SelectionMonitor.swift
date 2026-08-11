import AppKit
import ApplicationServices

struct CapturedSelection {
    let text: String
    let mouseLocation: NSPoint
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restoredItems = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    static func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

final class SelectionMonitor {
    var onSelection: ((CapturedSelection) -> Void)?
    var onSelectionCleared: (() -> Void)?

    private var mouseMonitor: Any?
    private var keyboardMonitor: Any?
    private var pollingTimer: Timer?
    private var pendingWork: DispatchWorkItem?
    private var isRunning = false
    private var lastFingerprint: String?
    private var suppressedText: String?
    private var clipboardFallbackInProgress = false
    private var ignoreKeyboardEventsUntil = Date.distantPast
    private var mouseDownLocation: NSPoint?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseDown {
                self.mouseDownLocation = NSEvent.mouseLocation
                return
            }

            let end = NSEvent.mouseLocation
            // If macOS withheld the corresponding mouse-down event, retain the
            // compatible fallback instead of breaking selection entirely.
            let didDrag = self.mouseDownLocation.map {
                hypot(end.x - $0.x, end.y - $0.y) >= 3
            } ?? true
            self.mouseDownLocation = nil
            let shouldTryClipboardFallback = Self.shouldUseClipboardFallback(
                didDrag: didDrag,
                clickCount: event.clickCount
            )
            self.scheduleCapture(
                after: 0.20,
                allowClipboardFallback: shouldTryClipboardFallback,
                clearWeChatIfMissing: !shouldTryClipboardFallback
            )
        }
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            guard let self, Date() >= self.ignoreKeyboardEventsUntil else { return }
            if event.modifierFlags.contains(.shift) {
                self.scheduleCapture(after: 0.12, allowClipboardFallback: true)
            } else if event.modifierFlags.contains(.command) {
                self.scheduleCapture(after: 0.12, allowClipboardFallback: false)
            }
        }

        // macOS can withhold global mouse events from background-only apps even
        // after Accessibility permission is granted. Polling the AX selection is
        // both lightweight and considerably more reliable across browsers,
        // Electron apps and native text views.
        let timer = Timer(timeInterval: 0.24, repeats: true) { [weak self] _ in
            self?.capture(allowClipboardFallback: false)
        }
        pollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        mouseMonitor = nil
        keyboardMonitor = nil
        pollingTimer?.invalidate()
        pollingTimer = nil
        pendingWork?.cancel()
        lastFingerprint = nil
        suppressedText = nil
        isRunning = false
    }

    func suppress(text: String) {
        suppressedText = normalized(text)
    }

    private func scheduleCapture(
        after delay: TimeInterval,
        allowClipboardFallback: Bool,
        clearWeChatIfMissing: Bool = false
    ) {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.capture(
                allowClipboardFallback: allowClipboardFallback,
                clearWeChatIfMissing: clearWeChatIfMissing
            )
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func capture(allowClipboardFallback: Bool, clearWeChatIfMissing: Bool = false) {
        guard AppSettings.isEnabled, AccessibilityPermission.isGranted else { return }
        guard !clipboardFallbackInProgress else { return }

        if let selection = currentSelection(), !selection.text.isEmpty {
            emit(text: selection.text, pid: selection.pid, at: NSEvent.mouseLocation)
            return
        }

        if isWeChatFrontmost {
            if allowClipboardFallback {
                captureWeChatSelectionUsingClipboard()
            } else if clearWeChatIfMissing {
                clearSelection()
            }
            // WeChat does not publish AXSelectedText. Polling must not hide a
            // toolbar that was just produced by the clipboard fallback.
            return
        }

        clearSelection()
    }

    private func emit(text: String, pid: pid_t, at point: NSPoint) {
        let clipped = String(text.prefix(20_000))
        let fingerprint = "\(pid):\(clipped)"
        guard clipped != suppressedText else {
            lastFingerprint = fingerprint
            return
        }
        guard fingerprint != lastFingerprint else { return }

        lastFingerprint = fingerprint
        suppressedText = nil
        onSelection?(CapturedSelection(text: clipped, mouseLocation: point))
    }

    private func clearSelection() {
        guard lastFingerprint != nil else { return }
        lastFingerprint = nil
        suppressedText = nil
        onSelectionCleared?()
    }

    static func shouldUseClipboardFallback(didDrag: Bool, clickCount: Int) -> Bool {
        didDrag || clickCount >= 2
    }

    static func isWeChatBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let bundleID = bundleIdentifier?.lowercased() else { return false }
        return bundleID == "com.tencent.xinwechat" ||
            bundleID == "com.tencent.wechat" ||
            (bundleID.hasPrefix("com.tencent.") && bundleID.contains("wechat"))
    }

    private var isWeChatFrontmost: Bool {
        Self.isWeChatBundleIdentifier(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func captureWeChatSelectionUsingClipboard() {
        guard !clipboardFallbackInProgress,
              let application = NSWorkspace.shared.frontmostApplication,
              Self.isWeChatBundleIdentifier(application.bundleIdentifier) else {
            clearSelection()
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let previousChangeCount = pasteboard.changeCount
        let anchor = NSEvent.mouseLocation
        let pid = application.processIdentifier

        clipboardFallbackInProgress = true
        ignoreKeyboardEventsUntil = Date().addingTimeInterval(0.80)
        postCommandCopy()
        awaitWeChatClipboard(
            snapshot: snapshot,
            previousChangeCount: previousChangeCount,
            anchor: anchor,
            pid: pid,
            attemptsRemaining: 5
        )
    }

    private func awaitWeChatClipboard(
        snapshot: PasteboardSnapshot,
        previousChangeCount: Int,
        anchor: NSPoint,
        pid: pid_t,
        attemptsRemaining: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            let didCopy = pasteboard.changeCount != previousChangeCount
            if !didCopy, attemptsRemaining > 1 {
                // Chromium-backed article views occasionally swallow the first
                // synthetic shortcut while finalizing the selection. Retry once
                // midway through the wait window instead of failing immediately.
                if attemptsRemaining == 3 { self.postCommandCopy() }
                self.awaitWeChatClipboard(
                    snapshot: snapshot,
                    previousChangeCount: previousChangeCount,
                    anchor: anchor,
                    pid: pid,
                    attemptsRemaining: attemptsRemaining - 1
                )
                return
            }

            let copied = didCopy ? pasteboard.string(forType: .string).map(self.normalized) : nil
            if didCopy { snapshot.restore(to: pasteboard) }
            self.clipboardFallbackInProgress = false
            guard didCopy, let copied, copied.count >= 2 else {
                self.clearSelection()
                return
            }
            self.emit(text: copied, pid: pid, at: anchor)
        }
    }

    private func postCommandCopy() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let commandFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        keyDown.flags = commandFlags
        keyUp.flags = commandFlags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func currentSelection() -> (text: String, pid: pid_t)? {
        let system = AXUIElementCreateSystemWide()
        var appValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appValue) == .success,
              let appValue else { return nil }

        let appElement = unsafeBitCast(appValue, to: AXUIElement.self)
        var pid: pid_t = 0
        AXUIElementGetPid(appElement, &pid)
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue else { return nil }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)

        if let selected = selectedText(from: focused) {
            return (selected, pid)
        }

        // In web views the focused child often does not expose AXSelectedText,
        // while one of its ancestors (usually AXWebArea) does.
        var current = focused
        for _ in 0..<8 {
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue else { break }
            let parent = unsafeBitCast(parentValue, to: AXUIElement.self)
            if let selected = selectedText(from: parent) {
                return (selected, pid)
            }
            current = parent
        }

        // Some native apps expose selection on the focused window instead.
        var windowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
           let windowValue {
            let window = unsafeBitCast(windowValue, to: AXUIElement.self)
            if let selected = selectedText(from: window) {
                return (selected, pid)
            }
        }
        return nil
    }

    private func selectedText(from element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
              let selected = selectedValue as? String else { return nil }
        let value = normalized(selected)
        return value.count >= 2 ? value : nil
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
