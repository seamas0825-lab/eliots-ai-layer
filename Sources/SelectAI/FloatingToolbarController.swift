import AppKit
import QuartzCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMousePopUpButton: NSPopUpButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ToolbarButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    private let idleColor: NSColor
    private let hoverColor: NSColor

    init(title: String, symbol: String, compact: Bool = false, emphasized: Bool = false) {
        idleColor = emphasized ? .controlAccentColor.withAlphaComponent(0.14) : .clear
        hoverColor = emphasized ? .controlAccentColor.withAlphaComponent(0.23) : .labelColor.withAlphaComponent(0.085)
        super.init(frame: .zero)

        self.title = title
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        font = .systemFont(ofSize: 12.5, weight: emphasized ? .semibold : .medium)
        contentTintColor = emphasized ? .controlAccentColor : .labelColor
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        toolTip = title
        setAccessibilityLabel(title)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = idleColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 34).isActive = true
        if compact { widthAnchor.constraint(equalToConstant: 26).isActive = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        animateBackground(to: hoverColor, scale: 1)
    }

    override func mouseExited(with event: NSEvent) {
        animateBackground(to: idleColor, scale: 1)
    }

    override func mouseDown(with event: NSEvent) {
        animateBackground(to: hoverColor, scale: 0.96)
        super.mouseDown(with: event)
        animateBackground(to: bounds.contains(convert(event.locationInWindow, from: nil)) ? hoverColor : idleColor, scale: 1)
    }

    private func animateBackground(to color: NSColor, scale: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = isEnabled ? 1 : 0.45
        }
        layer?.backgroundColor = color.cgColor
        layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }
}

final class FloatingToolbarController: NSObject {
    var onAction: ((AIAction, String, NSPoint) -> Void)?
    var onTranslateTarget: ((String, String, NSPoint) -> Void)?
    var onSearch: ((String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onSpeak: ((String) -> Void)?

    private let panel: FloatingPanel
    private var selectedText = ""
    private var anchor = NSPoint.zero
    private var animationToken = 0
    private lazy var languageMenu = makeLanguageMenu()
    private(set) var isInteracting = false

    override init() {
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 602, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    var isVisible: Bool { panel.isVisible }

    func show(text: String, at point: NSPoint) {
        selectedText = text
        anchor = point
        animationToken += 1

        let finalOrigin = constrainedOrigin(near: point)
        let finalFrame = NSRect(origin: finalOrigin, size: panel.frame.size)
        guard !panel.isVisible else {
            panel.alphaValue = 1
            panel.setFrame(finalFrame, display: true)
            panel.orderFrontRegardless()
            return
        }

        var startFrame = finalFrame
        startFrame.origin.y -= 5
        panel.alphaValue = 0
        panel.setFrame(startFrame, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.17
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    func hide(animated: Bool = true) {
        guard panel.isVisible else { return }
        animationToken += 1
        let token = animationToken
        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, token == self.animationToken else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })
    }

    private func constrainedOrigin(near point: NSPoint) -> NSPoint {
        let size = panel.frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        var x = point.x - size.width / 2
        var y = point.y - size.height - 14
        if y < visible.minY + 10 { y = point.y + 22 }
        x = min(max(x, visible.minX + 10), visible.maxX - size.width - 10)
        y = min(max(y, visible.minY + 10), visible.maxY - size.height - 10)
        return NSPoint(x: x, y: y)
    }

    private func configurePanel() {
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isMovable = false

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.52).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let translateButton = makeActionButton("翻译", symbol: "character.book.closed.fill", action: .translate, emphasized: true)
        translateButton.toolTip = "自动翻译：中文到英文，其他语言到中文"
        let languageButton = makeLanguageButton()
        stack.addArrangedSubview(translateButton)
        stack.addArrangedSubview(languageButton)
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(makeActionButton("总结", symbol: "text.badge.checkmark", action: .summarize))
        stack.addArrangedSubview(makeActionButton("解释", symbol: "lightbulb.min.fill", action: .explain))
        stack.addArrangedSubview(makeActionButton("润色", symbol: "wand.and.sparkles", action: .rewrite))
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(makeUtilityButton("搜索", symbol: "magnifyingglass", selector: #selector(searchText)))
        stack.addArrangedSubview(makeUtilityButton("复制", symbol: "doc.on.doc", selector: #selector(copyText)))
        stack.addArrangedSubview(makeUtilityButton("朗读", symbol: "speaker.wave.2.fill", selector: #selector(speakText)))
        stack.addArrangedSubview(makeActionButton("问 AI", symbol: "sparkles", action: .ask))

        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        panel.contentView = effect

        // Size the borderless panel from its controls instead of retaining the
        // original fixed preview width, which left a conspicuous empty tail.
        effect.layoutSubtreeIfNeeded()
        let fittedWidth = ceil(stack.fittingSize.width)
        panel.setContentSize(NSSize(width: fittedWidth, height: 52))
    }

    private func makeActionButton(
        _ title: String,
        symbol: String,
        action: AIAction,
        emphasized: Bool = false
    ) -> ToolbarButton {
        let button = ToolbarButton(title: title, symbol: symbol, emphasized: emphasized)
        button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
        button.target = self
        button.action = #selector(runAIAction(_:))
        return button
    }

    private func makeUtilityButton(_ title: String, symbol: String, selector: Selector) -> ToolbarButton {
        let button = ToolbarButton(title: title, symbol: symbol)
        button.target = self
        button.action = selector
        return button
    }

    private func separator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return view
    }

    private func makeLanguageButton() -> ToolbarButton {
        let button = ToolbarButton(title: "", symbol: "chevron.down", compact: true, emphasized: true)
        button.toolTip = "选择翻译目标语言"
        button.setAccessibilityLabel("选择翻译目标语言")
        button.target = self
        button.action = #selector(showLanguageMenu(_:))
        return button
    }

    private func makeLanguageMenu() -> NSMenu {
        let menu = NSMenu(title: "翻译目标语言")
        menu.title = "翻译目标语言"
        menu.autoenablesItems = false
        menu.minimumWidth = 310

        let automatic = NSMenuItem(
            title: "自动 · 中文 → 英文，其他 → 中文",
            action: #selector(runAutomaticTranslation),
            keyEquivalent: ""
        )
        automatic.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        automatic.target = self
        automatic.isEnabled = true
        menu.addItem(automatic)
        menu.addItem(.separator())

        for (index, language) in LanguageCatalog.ranked100.enumerated() {
            let item = NSMenuItem(
                title: LanguageCatalog.numberedTitle(for: language, at: index),
                action: #selector(runLanguageTranslation(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.promptName
            item.isEnabled = true
            if index == 0 {
                item.image = NSImage(systemSymbolName: "globe.americas.fill", accessibilityDescription: nil)
            } else if index == 1 {
                item.image = NSImage(systemSymbolName: "character.bubble.fill", accessibilityDescription: nil)
            }
            menu.addItem(item)
            if [19, 39, 59, 79].contains(index) { menu.addItem(.separator()) }
        }
        return menu
    }

    @objc private func showLanguageMenu(_ sender: NSButton) {
        guard !selectedText.isEmpty else { return }

        // NSMenu needs a key-capable owner while it tracks the pointer. Mark the
        // interaction first so selection polling cannot hide the toolbar while
        // the language menu is opening.
        isInteracting = true
        panel.makeKey()
        languageMenu.popUp(
            positioning: nil,
            at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY - 4),
            in: sender
        )
        isInteracting = false
    }

    @objc private func runAutomaticTranslation() {
        hide()
        onAction?(.translate, selectedText, anchor)
    }

    @objc private func runLanguageTranslation(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? String else { return }
        hide()
        onTranslateTarget?(target, selectedText, anchor)
    }

    @objc private func runAIAction(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let action = AIAction(rawValue: raw) else { return }
        hide()
        onAction?(action, selectedText, anchor)
    }

    @objc private func copyText() {
        hide()
        onCopy?(selectedText)
    }

    @objc private func searchText() {
        hide()
        onSearch?(selectedText)
    }

    @objc private func speakText() {
        hide()
        onSpeak?(selectedText)
    }
}
