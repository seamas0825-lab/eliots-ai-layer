import AppKit
import QuartzCore

final class ResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ResultPanelController: NSObject {
    var onTranslationTargetSelected: ((String?) -> Void)?

    private let panel: ResultPanel
    private let titleLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let spinner = NSProgressIndicator()
    private let copyButton = NSButton(title: "复制结果", target: nil, action: nil)
    private let languagePopup = FirstMousePopUpButton(frame: .zero, pullsDown: false)
    private var resultText = ""

    override init() {
        panel = ResultPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 360),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        configureUI()
    }

    func showLoading(
        title: String,
        at point: NSPoint,
        translationTarget: String? = nil,
        allowsLanguageSwitch: Bool = false
    ) {
        resultText = ""
        titleLabel.stringValue = title
        textView.string = "正在请求模型…"
        textView.textColor = .secondaryLabelColor
        spinner.startAnimation(nil)
        copyButton.isEnabled = false
        updateLanguagePopup(
            visible: allowsLanguageSwitch,
            target: translationTarget,
            enabled: false
        )
        position(near: point)
        revealPanel()
    }

    func showResult(
        _ text: String,
        title: String,
        translationTarget: String? = nil,
        allowsLanguageSwitch: Bool = false
    ) {
        resultText = text
        titleLabel.stringValue = title
        spinner.stopAnimation(nil)
        textView.textColor = .labelColor
        textView.string = text
        copyButton.isEnabled = true
        updateLanguagePopup(
            visible: allowsLanguageSwitch,
            target: translationTarget,
            enabled: true
        )
        textView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            textView.animator().alphaValue = 1
        }
        revealPanel(ifNeeded: true)
    }

    func showError(
        _ message: String,
        at point: NSPoint,
        translationTarget: String? = nil,
        allowsLanguageSwitch: Bool = false
    ) {
        resultText = ""
        titleLabel.stringValue = "请求失败"
        spinner.stopAnimation(nil)
        textView.textColor = .systemRed
        textView.string = message
        copyButton.isEnabled = false
        updateLanguagePopup(
            visible: allowsLanguageSwitch,
            target: translationTarget,
            enabled: true
        )
        position(near: point)
        revealPanel()
    }

    private func configureUI() {
        panel.title = "Eliot's AI Layer"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        // Menu-bar utilities normally stay inactive while the source app remains
        // frontmost. NSPanel hides itself on deactivation by default, which made
        // successful AI responses appear to do nothing.
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.worksWhenModal = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 240)

        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI 结果")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 8
        icon.layer?.cornerCurve = .continuous
        icon.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor

        titleLabel.font = .systemFont(ofSize: 15.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        configureLanguagePopup()

        let closeButton = NSButton(title: "完成", target: self, action: #selector(closePanel))
        closeButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyResult)
        copyButton.bezelStyle = .rounded
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeading

        let header = NSStackView(views: [icon, titleLabel, NSView(), languagePopup, spinner])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 14, height: 13)
        textView.isAutomaticLinkDetectionEnabled = true

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 12
        scroll.layer?.cornerCurve = .continuous
        scroll.layer?.borderWidth = 0.5
        scroll.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.42).cgColor
        scroll.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.45).cgColor

        let footer = NSStackView(views: [NSView(), copyButton, closeButton])
        footer.orientation = .horizontal
        footer.spacing = 8

        let stack = NSStackView(views: [header, scroll, footer])
        stack.orientation = .vertical
        stack.spacing = 13
        stack.edgeInsets = NSEdgeInsets(top: 38, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        panel.contentView = root
    }

    private func configureLanguagePopup() {
        languagePopup.controlSize = .small
        languagePopup.font = .systemFont(ofSize: 11.5, weight: .medium)
        languagePopup.bezelStyle = .rounded
        languagePopup.toolTip = "切换译文目标语言"
        languagePopup.setAccessibilityLabel("切换译文目标语言")
        languagePopup.target = self
        languagePopup.action = #selector(changeTranslationLanguage(_:))
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        languagePopup.widthAnchor.constraint(equalToConstant: 210).isActive = true

        languagePopup.removeAllItems()
        guard let menu = languagePopup.menu else { return }
        menu.autoenablesItems = false
        menu.minimumWidth = 310

        let automatic = NSMenuItem(title: "自动 · 中→英 / 其他→中", action: nil, keyEquivalent: "")
        automatic.representedObject = nil
        automatic.isEnabled = true
        automatic.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        menu.addItem(automatic)
        menu.addItem(.separator())

        for (index, language) in LanguageCatalog.ranked100.enumerated() {
            let item = NSMenuItem(
                title: LanguageCatalog.numberedTitle(for: language, at: index),
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = language.promptName
            item.isEnabled = true
            menu.addItem(item)
            if [19, 39, 59, 79].contains(index) { menu.addItem(.separator()) }
        }
        languagePopup.select(automatic)
        languagePopup.isHidden = true
    }

    private func updateLanguagePopup(visible: Bool, target: String?, enabled: Bool) {
        languagePopup.isHidden = !visible
        languagePopup.isEnabled = enabled
        guard visible else { return }

        if let target,
           let item = languagePopup.itemArray.first(where: { ($0.representedObject as? String) == target }) {
            languagePopup.select(item)
        } else if let automatic = languagePopup.item(at: 0) {
            languagePopup.select(automatic)
        }
    }

    private func position(near point: NSPoint) {
        let size = panel.frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        var x = point.x - size.width / 2
        var y = point.y - size.height - 24
        if y < visible.minY + 12 { y = point.y + 32 }
        x = min(max(x, visible.minX + 12), visible.maxX - size.width - 12)
        y = min(max(y, visible.minY + 12), visible.maxY - size.height - 12)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func revealPanel(ifNeeded: Bool = false) {
        if ifNeeded, panel.isVisible {
            panel.orderFrontRegardless()
            return
        }

        let finalFrame = panel.frame
        var startFrame = finalFrame
        startFrame.origin.y -= 7
        panel.alphaValue = 0
        panel.setFrame(startFrame, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    @objc private func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
    }

    @objc private func changeTranslationLanguage(_ sender: NSPopUpButton) {
        guard sender.selectedItem?.isSeparatorItem == false else { return }
        onTranslationTargetSelected?(sender.selectedItem?.representedObject as? String)
    }

    @objc private func closePanel() { panel.orderOut(nil) }
}
