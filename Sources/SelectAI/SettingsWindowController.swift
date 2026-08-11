import AppKit
import ServiceManagement

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onSaved: (() -> Void)?

    private let baseURLField = NSTextField()
    private let modelField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let languagePopup = NSPopUpButton()
    private let launchAtLoginSwitch = NSButton(checkboxWithTitle: "开机自动启动（推荐）", target: nil, action: nil)
    private let historyEnabledSwitch = NSButton(checkboxWithTitle: "自动记录剪贴板历史", target: nil, action: nil)
    private let shortcutRecorder = ShortcutRecorderButton(frame: .zero)
    private let historyLimitField = NSTextField()
    private let historyLimitStepper = NSStepper()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let testButton = NSButton(title: "测试连接", target: nil, action: nil)
    private var pendingShortcut = ClipboardShortcut.defaultValue

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 790),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Eliot's AI Layer 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        configureUI()
        loadValues()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        loadValues()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureUI() {
        guard let window else { return }
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Eliot's AI Layer")
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 42).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 42).isActive = true
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 11
        icon.layer?.cornerCurve = .continuous

        let title = NSTextField(labelWithString: "Eliot's AI Layer")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString: "在任何窗口选中文字，快速翻译、总结与解释")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 13)
        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3
        let header = NSStackView(views: [icon, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 13

        permissionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let permissionButton = NSButton(title: "打开设置", target: self, action: #selector(requestPermission))
        permissionButton.bezelStyle = .rounded
        let permissionRow = NSStackView(views: [permissionLabel, NSView(), permissionButton])
        permissionRow.orientation = .horizontal
        permissionRow.alignment = .centerY
        let permissionCard = card(containing: permissionRow)

        baseURLField.placeholderString = "https://api.openai.com/v1"
        modelField.placeholderString = "模型名称，例如 gpt-4.1-mini"
        apiKeyField.placeholderString = "API Key"

        languagePopup.addItems(withTitles: LanguageCatalog.outputLanguageNames)
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(toggleLaunchAtLogin)

        let form = NSGridView(views: [
            [label("API 地址"), baseURLField],
            [label("模型"), modelField],
            [label("API 密钥"), apiKeyField],
            [label("结果语言"), languagePopup]
        ])
        form.rowSpacing = 13
        form.columnSpacing = 14
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).width = 418

        let serviceTitle = sectionTitle("模型服务")
        let hint = NSTextField(wrappingLabelWithString: "兼容 OpenAI Chat Completions 接口。地址可填写到 /v1，密钥只保存在本机钥匙串。翻译目标语言可直接在悬浮工具条中选择。")
        hint.textColor = .tertiaryLabelColor
        hint.font = .systemFont(ofSize: 11.5)
        let formStack = NSStackView(views: [serviceTitle, form, hint])
        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.spacing = 13
        let formCard = card(containing: formStack)

        historyLimitField.alignment = .right
        historyLimitField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        historyLimitField.translatesAutoresizingMaskIntoConstraints = false
        historyLimitField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 1_000
        formatter.allowsFloats = false
        historyLimitField.formatter = formatter

        historyLimitStepper.minValue = 1
        historyLimitStepper.maxValue = 1_000
        historyLimitStepper.increment = 10
        historyLimitStepper.target = self
        historyLimitStepper.action = #selector(syncHistoryLimitFromStepper)
        shortcutRecorder.translatesAutoresizingMaskIntoConstraints = false
        shortcutRecorder.widthAnchor.constraint(equalToConstant: 150).isActive = true
        shortcutRecorder.onShortcutChanged = { [weak self] shortcut in
            self?.pendingShortcut = shortcut
        }

        let limitHint = NSTextField(labelWithString: "最多 1000 条")
        limitHint.font = .systemFont(ofSize: 11.5)
        limitHint.textColor = .secondaryLabelColor
        let limitRow = NSStackView(views: [historyLimitField, historyLimitStepper, limitHint])
        limitRow.orientation = .horizontal
        limitRow.alignment = .centerY
        limitRow.spacing = 6

        let clipboardGrid = NSGridView(views: [
            [label("呼出快捷键"), shortcutRecorder],
            [label("历史上限"), limitRow]
        ])
        clipboardGrid.rowSpacing = 10
        clipboardGrid.columnSpacing = 14
        clipboardGrid.column(at: 0).xPlacement = .trailing
        clipboardGrid.column(at: 1).xPlacement = .leading

        let clipboardTitle = sectionTitle("剪贴板")
        let clipboardHint = NSTextField(wrappingLabelWithString: "保存文本、图片、链接和文件位置。单击菜单栏图标呼出，双击历史条目即可粘贴回原窗口；标记为机密或临时的剪贴板内容不会记录。")
        clipboardHint.textColor = .tertiaryLabelColor
        clipboardHint.font = .systemFont(ofSize: 11.5)
        clipboardHint.translatesAutoresizingMaskIntoConstraints = false
        clipboardHint.widthAnchor.constraint(equalToConstant: 526).isActive = true
        let clipboardStack = NSStackView(views: [clipboardTitle, historyEnabledSwitch, clipboardGrid, clipboardHint])
        clipboardStack.orientation = .vertical
        clipboardStack.alignment = .leading
        clipboardStack.spacing = 10
        let clipboardCard = card(containing: clipboardStack)

        let behaviorTitle = sectionTitle("常规")
        let behaviorHint = NSTextField(labelWithString: "登录后在菜单栏安静运行，随时响应划词。")
        behaviorHint.textColor = .secondaryLabelColor
        behaviorHint.font = .systemFont(ofSize: 11.5)
        let behaviorStack = NSStackView(views: [behaviorTitle, launchAtLoginSwitch, behaviorHint])
        behaviorStack.orientation = .vertical
        behaviorStack.alignment = .leading
        behaviorStack.spacing = 9
        let behaviorCard = card(containing: behaviorStack)

        testButton.target = self
        testButton.action = #selector(testConnection)
        testButton.bezelStyle = .rounded
        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.bezelColor = .controlAccentColor
        saveButton.contentTintColor = .white
        saveButton.keyEquivalent = "\r"

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        let footer = NSStackView(views: [statusLabel, NSView(), testButton, saveButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10

        let stack = NSStackView(views: [header, permissionCard, formCard, clipboardCard, behaviorCard, NSView(), footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 45, left: 32, bottom: 24, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.widthAnchor.constraint(equalToConstant: 576),
            permissionCard.widthAnchor.constraint(equalToConstant: 576),
            formCard.widthAnchor.constraint(equalToConstant: 576),
            clipboardCard.widthAnchor.constraint(equalToConstant: 576),
            behaviorCard.widthAnchor.constraint(equalToConstant: 576),
            hint.widthAnchor.constraint(equalToConstant: 526),
            footer.widthAnchor.constraint(equalToConstant: 576)
        ])
        window.contentView = root
    }

    private func loadValues() {
        let config = AppSettings.configuration
        baseURLField.stringValue = config.baseURL
        modelField.stringValue = config.model
        apiKeyField.stringValue = config.apiKey
        languagePopup.selectItem(withTitle: LanguageCatalog.normalizedOutputLanguage(config.outputLanguage))
        historyEnabledSwitch.state = AppSettings.clipboardHistoryEnabled ? .on : .off
        let historyLimit = AppSettings.clipboardHistoryLimit
        historyLimitField.integerValue = historyLimit
        historyLimitStepper.integerValue = historyLimit
        pendingShortcut = AppSettings.clipboardShortcut
        shortcutRecorder.setShortcut(pendingShortcut)
        if #available(macOS 13.0, *) {
            launchAtLoginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginSwitch.isEnabled = false
        }
        updatePermissionStatus()
        statusLabel.stringValue = ""
    }

    private func currentConfiguration() -> APIConfiguration {
        APIConfiguration(
            baseURL: baseURLField.stringValue,
            model: modelField.stringValue,
            apiKey: apiKeyField.stringValue,
            outputLanguage: languagePopup.titleOfSelectedItem ?? "简体中文（普通话）"
        )
    }

    private func updatePermissionStatus() {
        if AccessibilityPermission.isGranted {
            permissionLabel.stringValue = "✓ 辅助功能权限已授予"
            permissionLabel.textColor = .systemGreen
        } else {
            permissionLabel.stringValue = "当前运行版本未获得辅助功能权限"
            permissionLabel.textColor = .systemOrange
        }
    }

    @objc private func requestPermission() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSystemSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.updatePermissionStatus() }
    }

    @objc private func save() {
        let config = currentConfiguration()
        guard config.isComplete else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "请填写完整的 API 配置"
            return
        }
        AppSettings.configuration = config
        AppSettings.clipboardHistoryEnabled = historyEnabledSwitch.state == .on
        AppSettings.clipboardHistoryLimit = historyLimitField.integerValue
        AppSettings.clipboardShortcut = pendingShortcut
        historyLimitField.integerValue = AppSettings.clipboardHistoryLimit
        historyLimitStepper.integerValue = AppSettings.clipboardHistoryLimit
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "已保存"
        onSaved?()
    }

    @objc private func syncHistoryLimitFromStepper() {
        historyLimitField.integerValue = historyLimitStepper.integerValue
    }

    @objc private func testConnection() {
        let config = currentConfiguration()
        guard config.isComplete else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "请先填写完整配置"
            return
        }
        AppSettings.configuration = config
        testButton.isEnabled = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在连接…"
        Task { [weak self] in
            do {
                let result = try await AIClient().testConnection()
                await MainActor.run {
                    self?.statusLabel.textColor = .systemGreen
                    self?.statusLabel.stringValue = result
                    self?.testButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self?.statusLabel.textColor = .systemRed
                    self?.statusLabel.stringValue = error.localizedDescription
                    self?.testButton.isEnabled = true
                }
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLoginSwitch.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            statusLabel.stringValue = ""
        } catch {
            launchAtLoginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "开机启动设置失败：请先把应用移到“应用程序”文件夹"
        }
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13, weight: .medium)
        return field
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13.5, weight: .semibold)
        return field
    }

    private func card(containing content: NSView) -> NSVisualEffectView {
        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
