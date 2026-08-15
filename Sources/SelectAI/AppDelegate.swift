import AppKit
import AVFoundation

enum AppEvents {
    static let previewToolbar = Notification.Name("com.seamaslee.selectai.preview-toolbar")
    static let previewMarkdown = Notification.Name("com.seamaslee.selectai.preview-markdown")
    static let showSettings = Notification.Name("com.seamaslee.selectai.show-settings")
    static let showClipboard = Notification.Name("com.seamaslee.selectai.show-clipboard")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SelectionMonitor()
    private let toolbar = FloatingToolbarController()
    private let resultPanel = ResultPanelController()
    private let settings = SettingsWindowController()
    private let aiClient = AIClient()
    private let speech = AVSpeechSynthesizer()
    private let clipboardManager = ClipboardHistoryManager()
    private var clipboardPanel: ClipboardPanelController!
    private var globalHotKey: GlobalHotKey?
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private var permissionTimer: Timer?
    private var previewObserver: NSObjectProtocol?
    private var markdownPreviewObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var clipboardObserver: NSObjectProtocol?
    private var applicationActivationObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?
    private var activeTranslationContext: (text: String, point: NSPoint)?
    private var activeRequestID: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        clipboardPanel = ClipboardPanelController(manager: clipboardManager)
        globalHotKey = GlobalHotKey { [weak self] in self?.toggleClipboard(from: nil) }
        globalHotKey?.update(shortcut: AppSettings.clipboardShortcut)
        configureStatusItem()
        configureCallbacks()
        previewObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppEvents.previewToolbar,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.previewToolbar()
        }
        markdownPreviewObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppEvents.previewMarkdown,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.previewMarkdownResult()
        }
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppEvents.showSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openSettings()
        }
        clipboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppEvents.showClipboard,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.toggleClipboard(from: self?.statusItem.button)
        }
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self.lastExternalApplication = app
        }
        monitor.start()
        clipboardManager.start()

        if CommandLine.arguments.contains("--ui-preview") {
            settings.showWindow(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.previewToolbar()
            }
            return
        }

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
            settings.showWindow(nil)
        } else if !AppSettings.configuration.isComplete {
            settings.showWindow(nil)
        }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshMenuState()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        clipboardManager.stop()
        permissionTimer?.invalidate()
        if let previewObserver { DistributedNotificationCenter.default().removeObserver(previewObserver) }
        if let markdownPreviewObserver { DistributedNotificationCenter.default().removeObserver(markdownPreviewObserver) }
        if let settingsObserver { DistributedNotificationCenter.default().removeObserver(settingsObserver) }
        if let clipboardObserver { DistributedNotificationCenter.default().removeObserver(clipboardObserver) }
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Eliot's AI Layer")
        statusItem.button?.toolTip = "Eliot's AI Layer"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let toggle = NSMenuItem(title: "启用划词工具", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.tag = 100
        statusMenu.addItem(toggle)
        statusMenu.addItem(NSMenuItem.separator())

        let clipboardItem = NSMenuItem(title: "打开剪贴板", action: #selector(openClipboardFromMenu), keyEquivalent: "")
        clipboardItem.target = self
        statusMenu.addItem(clipboardItem)
        statusMenu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "API 与权限设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu.addItem(settingsItem)
        let permissionItem = NSMenuItem(title: "打开辅助功能设置", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissionItem.target = self
        statusMenu.addItem(permissionItem)
        let previewItem = NSMenuItem(title: "预览划词工具条", action: #selector(previewToolbar), keyEquivalent: "")
        previewItem.target = self
        statusMenu.addItem(previewItem)
        statusMenu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "退出 Eliot's AI Layer", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        statusMenu.addItem(quit)
        refreshMenuState()
    }

    private func configureCallbacks() {
        monitor.onSelection = { [weak self] selection in
            self?.toolbar.show(text: selection.text, at: selection.mouseLocation)
        }
        monitor.onSelectionCleared = { [weak self] in
            guard let self, !self.toolbar.isInteracting else { return }
            self.toolbar.hide()
        }
        monitor.onClipboardFallbackStateChanged = { [weak self] isActive in
            guard let self else { return }
            if isActive {
                self.clipboardManager.suspendCapture()
            } else {
                self.clipboardManager.resumeCaptureAfterInternalChange()
            }
        }
        toolbar.onAction = { [weak self] action, text, point in
            self?.monitor.suppress(text: text)
            self?.handle(action: action, text: text, point: point)
        }
        toolbar.onTranslateTarget = { [weak self] target, text, point in
            self?.monitor.suppress(text: text)
            self?.handle(action: .translate, text: text, point: point, translationTarget: target)
        }
        toolbar.onSearch = { [weak self] text in
            self?.monitor.suppress(text: text)
            guard let url = WebSearch.googleURL(for: text) else { return }
            NSWorkspace.shared.open(url)
        }
        toolbar.onCopy = { [weak self] text in
            self?.monitor.suppress(text: text)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        toolbar.onSpeak = { [weak self] text in
            self?.monitor.suppress(text: text)
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.48
            self?.speech.speak(utterance)
        }
        resultPanel.onTranslationTargetSelected = { [weak self] target in
            guard let self, let context = self.activeTranslationContext else { return }
            self.handle(
                action: .translate,
                text: context.text,
                point: context.point,
                translationTarget: target
            )
        }
        clipboardPanel.onPaste = { [weak self] entry, target in
            self?.pasteClipboardEntry(entry, into: target)
        }
        clipboardPanel.onTranslate = { [weak self] text, targetLanguage, point in
            self?.handle(
                action: .translate,
                text: text,
                point: point,
                translationTarget: targetLanguage
            )
        }
        clipboardPanel.onOpenSettings = { [weak self] in self?.openSettings() }
        clipboardManager.onChange = { [weak self] _ in
            guard let self else { return }
            if self.clipboardPanel.isVisible { self.clipboardPanel.refresh() }
            self.refreshMenuState()
        }
        settings.onSaved = { [weak self] in
            guard let self else { return }
            self.globalHotKey?.update(shortcut: AppSettings.clipboardShortcut)
            self.clipboardManager.updateLimit()
            self.refreshMenuState()
        }
    }

    private func handle(
        action: AIAction,
        text: String,
        point: NSPoint,
        translationTarget: String? = nil
    ) {
        let isTranslation = action == .translate
        if isTranslation {
            activeTranslationContext = (text, point)
        } else {
            activeTranslationContext = nil
        }

        guard AppSettings.configuration.isComplete else {
            resultPanel.showError(
                "请先填写 API 地址、模型和密钥。",
                at: point,
                translationTarget: translationTarget,
                allowsLanguageSwitch: isTranslation
            )
            settings.showWindow(nil)
            return
        }

        var customQuestion: String?
        if action == .ask {
            let alert = NSAlert()
            alert.messageText = "针对选中文字提问"
            alert.informativeText = "输入你的问题："
            alert.addButton(withTitle: "发送")
            alert.addButton(withTitle: "取消")
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
            input.placeholderString = "例如：这段话的核心论点是什么？"
            alert.accessoryView = input
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn,
                  !input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            customQuestion = input.stringValue
        }

        let resultTitle = translationTarget.map { "翻译为 \($0)" } ?? action.rawValue
        let requestID = UUID()
        activeRequestID = requestID
        resultPanel.showLoading(
            title: resultTitle,
            at: point,
            translationTarget: translationTarget,
            allowsLanguageSwitch: isTranslation,
            statusText: action.requiresWebResearch ? "正在核验信息并组织答案…" : "正在请求模型…"
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await aiClient.run(
                    action: action,
                    text: text,
                    customQuestion: customQuestion,
                    translationTarget: translationTarget
                )
                await MainActor.run {
                    guard self.activeRequestID == requestID else { return }
                    let finalTitle: String
                    switch result.webSearchState {
                    case .enabled: finalTitle = "\(resultTitle) · 已联网"
                    case .unavailable: finalTitle = "\(resultTitle) · 未联网"
                    case .notRequested: finalTitle = resultTitle
                    }
                    self.resultPanel.showResult(
                        result.markdown,
                        title: finalTitle,
                        translationTarget: translationTarget,
                        allowsLanguageSwitch: isTranslation
                    )
                }
            } catch {
                await MainActor.run {
                    guard self.activeRequestID == requestID else { return }
                    self.resultPanel.showError(
                        error.localizedDescription,
                        at: point,
                        translationTarget: translationTarget,
                        allowsLanguageSwitch: isTranslation
                    )
                }
            }
        }
    }

    private func refreshMenuState() {
        guard let item = statusMenu.item(withTag: 100) else { return }
        item.state = AppSettings.isEnabled ? .on : .off
        let permissionSuffix = AccessibilityPermission.isGranted ? "" : " · 需要权限"
        let shortcut = AppSettings.clipboardShortcut.displayString
        statusItem.button?.toolTip = "Eliot's AI Layer · 剪贴板 \(clipboardManager.entries.count) 条 · \(shortcut)\(permissionSuffix)"
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else {
            toggleClipboard(from: sender)
        }
    }

    @objc private func openClipboardFromMenu() { toggleClipboard(from: statusItem.button) }

    private func toggleClipboard(from statusButton: NSStatusBarButton?) {
        let current = NSWorkspace.shared.frontmostApplication
        if let current, current.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApplication = current
        }
        clipboardPanel.toggle(from: statusButton, target: lastExternalApplication)
    }

    private func pasteClipboardEntry(_ entry: ClipboardEntry, into application: NSRunningApplication?) {
        guard clipboardManager.restoreToPasteboard(entry) else {
            NSSound.beep()
            return
        }
        clipboardPanel.hide()
        guard let application else { return }
        NSApp.deactivate()
        application.unhide()
        application.activate(options: [.activateAllWindows])
        postCommandPaste(whenReadyFor: application, attempt: 0)
    }

    private func postCommandPaste(whenReadyFor application: NSRunningApplication, attempt: Int) {
        guard !application.isTerminated else { return }
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
        if isFrontmost {
            // WeChat's custom input view needs a little longer than a native text field to
            // reclaim first responder status after our floating panel gives up focus.
            let bundleIdentifier = application.bundleIdentifier?.lowercased() ?? ""
            let activationDelay = bundleIdentifier.contains("wechat") ? 0.24 : 0.10
            DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) { Self.postCommandPaste() }
            return
        }

        guard attempt < 14 else {
            NSSound.beep()
            return
        }
        application.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.postCommandPaste(whenReadyFor: application, attempt: attempt + 1)
        }
    }

    private static func postCommandPaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        // The low modifier bit mirrors physical left/right command state and is
        // required by some Chromium/WebView-based editors.
        let commandFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        down.flags = commandFlags
        up.flags = commandFlags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        AppSettings.isEnabled.toggle()
        if !AppSettings.isEnabled { toolbar.hide() }
        refreshMenuState()
    }

    @objc private func openSettings() { settings.showWindow(nil) }
    @objc private func openAccessibilitySettings() { AccessibilityPermission.openSystemSettings() }
    @objc private func previewToolbar() {
        let point: NSPoint
        if let frame = settings.window?.frame, settings.window?.isVisible == true {
            point = NSPoint(x: frame.midX, y: frame.midY + 120)
        } else {
            point = NSEvent.mouseLocation
        }
        toolbar.show(text: "这是一段用于预览划词工具条的示例文字。", at: point)
    }
    private func previewMarkdownResult() {
        let sample = """
        ## 一句话说明

        这是一段支持 **Markdown 排版** 的解释结果，不再显示原始星号。

        ### 关键背景

        - 清晰呈现重点和层级
        - 支持 `行内代码`、引用与可点击链接
        - 来源使用标准 Markdown 链接

        > **最新核验**：涉及变化的信息会标注具体日期与联网状态。

        | 能力 | 状态 |
        | --- | --- |
        | 标题与列表 | 已支持 |
        | 链接与代码 | 已支持 |

        ### 参考来源

        1. [OpenAI Web Search](https://platform.openai.com/docs/guides/tools-web-search)
        """
        resultPanel.showResult(sample, title: "解释 · 已联网")
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
