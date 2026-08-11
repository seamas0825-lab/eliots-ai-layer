import AppKit
import QuartzCore
import QuickLookUI

final class ClipboardPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class ClipboardEntryCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(wrappingLabelWithString: "")
    private let detailField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 38).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 38).isActive = true
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 9
        iconView.layer?.cornerCurve = .continuous
        iconView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor

        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingTail
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingMiddle

        let labels = NSStackView(views: [titleField, detailField])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        let row = NSStackView(views: [iconView, labels])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 11
        row.edgeInsets = NSEdgeInsets(top: 7, left: 9, bottom: 7, right: 9)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            labels.widthAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(entry: ClipboardEntry, image: NSImage?, detail: String) {
        titleField.stringValue = entry.title.isEmpty ? entry.kind.displayName : entry.title
        detailField.stringValue = detail
        if let image {
            iconView.image = image
            iconView.contentTintColor = nil
        } else {
            iconView.image = NSImage(systemSymbolName: entry.kind.symbolName, accessibilityDescription: entry.kind.displayName)
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            iconView.contentTintColor = .controlAccentColor
        }
    }
}

final class ClipboardPreviewView: NSVisualEffectView {
    var onOpenImage: (() -> Void)?

    private let headingField = NSTextField(labelWithString: "预览")
    private let imageView = NSImageView()
    private let textField = NSTextField(wrappingLabelWithString: "")
    private let detailField = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "打开大图", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.42).cgColor

        headingField.font = .systemFont(ofSize: 12.5, weight: .semibold)
        headingField.textColor = .secondaryLabelColor

        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 9
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.035).cgColor
        imageView.setAccessibilityLabel("剪贴板图片预览")

        textField.font = .systemFont(ofSize: 13)
        textField.textColor = .labelColor
        textField.maximumNumberOfLines = 14
        textField.lineBreakMode = .byTruncatingTail
        textField.alignment = .left

        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .secondaryLabelColor
        detailField.maximumNumberOfLines = 3

        openButton.target = self
        openButton.action = #selector(openImage)
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)
        openButton.imagePosition = .imageLeading
        openButton.setAccessibilityLabel("打开图片大图预览")

        let stack = NSStackView(views: [headingField, imageView, textField, detailField, openButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 250),
            textField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            detailField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24)
        ])

        showPlaceholder()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(entry: ClipboardEntry?, image: NSImage?, detail: String?) {
        guard let entry else {
            showPlaceholder()
            return
        }

        headingField.stringValue = entry.kind == .image ? "图片预览" : entry.kind.displayName
        detailField.stringValue = detail ?? ""

        if entry.kind == .image, let image {
            imageView.image = image
            imageView.isHidden = false
            textField.isHidden = true
            openButton.isHidden = false
            let representation = image.representations.max {
                ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
            }
            let dimensions = representation.map { "\($0.pixelsWide) × \($0.pixelsHigh) 像素" } ?? "图片"
            detailField.stringValue = [dimensions, detail].compactMap { $0 }.joined(separator: "\n")
        } else {
            imageView.image = nil
            imageView.isHidden = true
            textField.isHidden = false
            openButton.isHidden = true
            switch entry.kind {
            case .text, .link:
                textField.stringValue = String((entry.text ?? entry.title).prefix(1_200))
            case .files:
                textField.stringValue = entry.filePaths.joined(separator: "\n")
            case .image:
                textField.stringValue = "图片缓存已不可用"
            }
        }
    }

    private func showPlaceholder() {
        headingField.stringValue = "预览"
        imageView.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.isHidden = false
        textField.isHidden = true
        detailField.stringValue = "选择一条剪贴板记录"
        openButton.isHidden = true
    }

    @objc private func openImage() { onOpenImage?() }
}

final class ClipboardQuickLookController: NSObject, QLPreviewPanelDataSource {
    private var previewURL: URL?

    func show(url: URL) {
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.currentPreviewItemIndex = 0
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }
}

final class ClipboardPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onPaste: ((ClipboardEntry, NSRunningApplication?) -> Void)?
    var onTranslate: ((String, String?, NSPoint) -> Void)?
    var onOpenSettings: (() -> Void)?

    private let manager: ClipboardHistoryManager
    private let panel: ClipboardPanel
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "还没有剪贴板记录")
    private let translateButton = NSButton(title: "翻译", target: nil, action: nil)
    private let translateLanguageButton = NSButton(
        image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "选择翻译目标语言") ?? NSImage(),
        target: nil,
        action: nil
    )
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private let pasteButton = NSButton(title: "粘贴", target: nil, action: nil)
    private let previewView = ClipboardPreviewView()
    private let quickLookController = ClipboardQuickLookController()
    private var filteredEntries: [ClipboardEntry] = []
    private var targetApplication: NSRunningApplication?
    private let relativeDateFormatter = RelativeDateTimeFormatter()
    private lazy var translationLanguageMenu = makeTranslationLanguageMenu()

    init(manager: ClipboardHistoryManager) {
        self.manager = manager
        panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 590),
            styleMask: [.nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        refresh()
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(from statusButton: NSStatusBarButton?, target: NSRunningApplication?) {
        if panel.isVisible {
            hide()
        } else {
            show(from: statusButton, target: target)
        }
    }

    func show(from statusButton: NSStatusBarButton?, target: NSRunningApplication?) {
        targetApplication = target
        searchField.stringValue = ""
        refresh()
        position(from: statusButton)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(searchField)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    func refresh() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredEntries = manager.entries
        } else {
            filteredEntries = manager.entries.filter { entry in
                entry.title.lowercased().contains(query) ||
                    entry.filePaths.joined(separator: " ").lowercased().contains(query)
            }
        }
        countLabel.stringValue = "\(manager.entries.count) 条"
        tableView.reloadData()
        emptyLabel.isHidden = !filteredEntries.isEmpty
        if !filteredEntries.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filteredEntries.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 62 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filteredEntries.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ClipboardEntryCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ClipboardEntryCellView
            ?? ClipboardEntryCellView(frame: .zero)
        cell.identifier = identifier
        let entry = filteredEntries[row]
        cell.configure(
            entry: entry,
            image: entry.kind == .image ? manager.image(for: entry) : nil,
            detail: detailText(for: entry)
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        updatePreview()
    }

    func controlTextDidChange(_ obj: Notification) { refresh() }

    private func configurePanel() {
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 660, height: 440)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.onCancel = { [weak self] in self?.hide() }

        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "剪贴板")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 9
        icon.layer?.cornerCurve = .continuous
        icon.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor

        let title = NSTextField(labelWithString: "剪贴板")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        countLabel.textColor = .secondaryLabelColor

        let settingsButton = NSButton(
            image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置") ?? NSImage(),
            target: self,
            action: #selector(openSettings)
        )
        settingsButton.isBordered = false
        settingsButton.toolTip = "剪贴板设置"
        settingsButton.setAccessibilityLabel("剪贴板设置")
        let clearButton = NSButton(title: "清空", target: self, action: #selector(clearHistory))
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small

        let header = NSStackView(views: [icon, title, countLabel, NSView(), clearButton, settingsButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 9

        searchField.placeholderString = "搜索文本、链接或文件名"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.font = .systemFont(ofSize: 13)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("History"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 62
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClickRow)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 12
        scroll.layer?.cornerCurve = .continuous
        scroll.layer?.borderWidth = 0.5
        scroll.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        scroll.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35).cgColor

        previewView.onOpenImage = { [weak self] in self?.openImagePreview() }
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.widthAnchor.constraint(equalToConstant: 230).isActive = true

        let body = NSStackView(views: [scroll, previewView])
        body.orientation = .horizontal
        body.alignment = .top
        body.spacing = 12
        body.distribution = .fill

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyLabel)

        let hint = NSTextField(labelWithString: "双击条目即可粘贴到原窗口")
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = .secondaryLabelColor

        translateButton.target = self
        translateButton.action = #selector(translateSelectedAutomatically)
        translateButton.bezelStyle = .rounded
        translateButton.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil)
        translateButton.imagePosition = .imageLeading
        translateButton.toolTip = "自动翻译：中文到英文，其他语言到中文"

        translateLanguageButton.target = self
        translateLanguageButton.action = #selector(showTranslationLanguageMenu(_:))
        translateLanguageButton.bezelStyle = .rounded
        translateLanguageButton.imagePosition = .imageOnly
        translateLanguageButton.toolTip = "选择翻译目标语言"
        translateLanguageButton.setAccessibilityLabel("选择剪贴板翻译目标语言")
        translateLanguageButton.translatesAutoresizingMaskIntoConstraints = false
        translateLanguageButton.widthAnchor.constraint(equalToConstant: 30).isActive = true

        copyButton.target = self
        copyButton.action = #selector(copySelected)
        copyButton.bezelStyle = .rounded
        pasteButton.target = self
        pasteButton.action = #selector(pasteSelected)
        pasteButton.bezelStyle = .rounded
        pasteButton.bezelColor = .controlAccentColor
        pasteButton.contentTintColor = .white

        let footer = NSStackView(views: [
            hint,
            NSView(),
            translateButton,
            translateLanguageButton,
            copyButton,
            pasteButton
        ])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let stack = NSStackView(views: [header, searchField, body, footer])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            body.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            scroll.heightAnchor.constraint(equalTo: body.heightAnchor),
            previewView.heightAnchor.constraint(equalTo: body.heightAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
        panel.contentView = root
    }

    private func position(from statusButton: NSStatusBarButton?) {
        let size = panel.frame.size
        let screen: NSScreen
        let anchor: NSPoint

        if let statusButton, let window = statusButton.window {
            let rect = window.convertToScreen(statusButton.convert(statusButton.bounds, to: nil))
            screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
            anchor = NSPoint(x: rect.midX, y: rect.minY - 7)
        } else {
            let point = NSEvent.mouseLocation
            screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens[0]
            anchor = point
        }

        let visible = screen.visibleFrame
        var x = anchor.x - size.width / 2
        var y = anchor.y - size.height
        x = min(max(x, visible.minX + 10), visible.maxX - size.width - 10)
        y = min(max(y, visible.minY + 10), visible.maxY - size.height - 10)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func detailText(for entry: ClipboardEntry) -> String {
        let relative = relativeDateFormatter.localizedString(for: entry.createdAt, relativeTo: Date())
        if entry.kind == .files {
            let missing = entry.filePaths.filter { !FileManager.default.fileExists(atPath: $0) }.count
            return missing > 0
                ? "\(entry.filePaths.count) 个文件 · \(missing) 个位置已失效 · \(relative)"
                : "\(entry.filePaths.count) 个文件 · 保存原位置 · \(relative)"
        }
        return "\(entry.kind.displayName) · \(relative)"
    }

    private var selectedEntry: ClipboardEntry? {
        guard filteredEntries.indices.contains(tableView.selectedRow) else { return nil }
        return filteredEntries[tableView.selectedRow]
    }

    private func updateButtons() {
        let enabled = selectedEntry != nil
        let canTranslate = selectedEntry?.translatableText != nil
        translateButton.isEnabled = canTranslate
        translateLanguageButton.isEnabled = canTranslate
        copyButton.isEnabled = enabled
        pasteButton.isEnabled = enabled
    }

    private func makeTranslationLanguageMenu() -> NSMenu {
        let menu = NSMenu(title: "翻译目标语言")
        menu.autoenablesItems = false
        menu.minimumWidth = 310

        let automatic = NSMenuItem(
            title: "自动 · 中文 → 英文，其他 → 中文",
            action: #selector(translateSelectedAutomatically),
            keyEquivalent: ""
        )
        automatic.target = self
        automatic.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        automatic.isEnabled = true
        menu.addItem(automatic)
        menu.addItem(.separator())

        for (index, language) in LanguageCatalog.ranked100.enumerated() {
            let item = NSMenuItem(
                title: LanguageCatalog.numberedTitle(for: language, at: index),
                action: #selector(translateSelectedToLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.promptName
            item.isEnabled = true
            menu.addItem(item)
            if [19, 39, 59, 79].contains(index) { menu.addItem(.separator()) }
        }
        return menu
    }

    private func updatePreview() {
        guard let entry = selectedEntry else {
            previewView.configure(entry: nil, image: nil, detail: nil)
            return
        }
        previewView.configure(
            entry: entry,
            image: entry.kind == .image ? manager.image(for: entry) : nil,
            detail: detailText(for: entry)
        )
    }

    private func openImagePreview() {
        guard let entry = selectedEntry,
              let url = manager.imageURL(for: entry) else {
            NSSound.beep()
            return
        }
        quickLookController.show(url: url)
    }

    @objc private func doubleClickRow() { pasteSelected() }

    @objc private func copySelected() {
        guard let entry = selectedEntry, manager.restoreToPasteboard(entry) else {
            NSSound.beep()
            return
        }
        hide()
    }

    @objc private func pasteSelected() {
        guard let entry = selectedEntry else { return }
        onPaste?(entry, targetApplication)
    }

    @objc private func showTranslationLanguageMenu(_ sender: NSButton) {
        guard selectedEntry?.translatableText != nil else { return }
        translationLanguageMenu.popUp(
            positioning: nil,
            at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY - 4),
            in: sender
        )
    }

    @objc private func translateSelectedAutomatically() {
        translateSelected(to: nil)
    }

    @objc private func translateSelectedToLanguage(_ sender: NSMenuItem) {
        translateSelected(to: sender.representedObject as? String)
    }

    private func translateSelected(to targetLanguage: String?) {
        guard let text = selectedEntry?.translatableText else {
            NSSound.beep()
            return
        }
        let point = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        hide()
        onTranslate?(text, targetLanguage, point)
    }

    @objc private func openSettings() {
        hide()
        onOpenSettings?()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空剪贴板历史？"
        alert.informativeText = "这会删除 Eliot's AI Layer 保存的剪贴板记录和图片缓存，不会影响系统当前剪贴板。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "清空")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        manager.clear()
        refresh()
    }
}
