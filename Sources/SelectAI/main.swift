import AppKit
import ServiceManagement

if CommandLine.arguments.contains("--preview-toolbar") {
    DistributedNotificationCenter.default().postNotificationName(
        AppEvents.previewToolbar,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    exit(0)
}

if CommandLine.arguments.contains("--show-settings") {
    DistributedNotificationCenter.default().postNotificationName(
        AppEvents.showSettings,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    exit(0)
}

if CommandLine.arguments.contains("--show-clipboard") {
    DistributedNotificationCenter.default().postNotificationName(
        AppEvents.showClipboard,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    exit(0)
}

if CommandLine.arguments.contains("--permission-status") {
    print(AccessibilityPermission.isGranted ? "ACCESSIBILITY GRANTED" : "ACCESSIBILITY NOT GRANTED")
    exit(AccessibilityPermission.isGranted ? 0 : 2)
}

if CommandLine.arguments.contains("--login-unregister") {
    if #available(macOS 13.0, *) {
        do {
            try SMAppService.mainApp.unregister()
            print("LOGIN ITEM UNREGISTERED")
            exit(0)
        } catch {
            fputs("LOGIN ITEM UNREGISTER FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

if CommandLine.arguments.contains("--login-register") {
    if #available(macOS 13.0, *) {
        do {
            try SMAppService.mainApp.register()
            print("LOGIN ITEM REGISTERED")
            exit(0)
        } catch {
            fputs("LOGIN ITEM REGISTER FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    var failures = 0
    func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("PASS \(name)")
        } else {
            failures += 1
            print("FAIL \(name)")
        }
    }

    expect(
        AIClient.chatCompletionsURL(from: "https://example.com/v1")?.absoluteString ==
            "https://example.com/v1/chat/completions",
        "补全 chat/completions 路径"
    )
    expect(
        AIClient.chatCompletionsURL(from: "https://example.com/openai/v1/chat/completions/")?.absoluteString ==
            "https://example.com/openai/v1/chat/completions",
        "保留完整接口路径"
    )
    expect(AIClient.chatCompletionsURL(from: "file:///tmp/api") == nil, "拒绝非 HTTP 地址")
    expect(
        APIConfiguration(baseURL: "https://example.com/v1", model: "model", apiKey: "key", outputLanguage: "简体中文").isComplete,
        "接受完整配置"
    )
    expect(
        !APIConfiguration(baseURL: "https://example.com/v1", model: "", apiKey: "key", outputLanguage: "简体中文").isComplete,
        "拒绝缺少模型的配置"
    )
    expect(LanguageCatalog.ranked100.count == 100, "提供 100 种目标语言")
    expect(Set(LanguageCatalog.outputLanguageNames).count == 100, "目标语言名称不重复")
    expect(LanguageCatalog.ranked100.first?.promptName == "英语", "语言按总使用人数排序")
    expect(LanguageCatalog.normalizedOutputLanguage("简体中文") == "简体中文（普通话）", "迁移旧语言设置")
    expect(AppSettings.clampedClipboardLimit(0) == 1, "剪贴板历史下限为 1")
    expect(AppSettings.clampedClipboardLimit(1_500) == 1_000, "剪贴板历史上限为 1000")
    expect(ClipboardShortcut.defaultValue.displayString == "⌥⌘V", "默认剪贴板快捷键")
    expect(
        SelectionMonitor.shouldUseClipboardFallback(didDrag: false, clickCount: 2),
        "微信双击选词启用复制兜底"
    )
    expect(
        SelectionMonitor.isWeChatBundleIdentifier("com.tencent.flue.WeChatAppEx"),
        "识别微信公众号文章子进程"
    )
    let testPasteboard = NSPasteboard(name: NSPasteboard.Name("com.seamaslee.selectai.tests.\(UUID().uuidString)"))
    let testHistoryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("SelectAI-ClipboardTests-\(UUID().uuidString)", isDirectory: true)
    let testHistory = ClipboardHistoryManager(pasteboard: testPasteboard, rootDirectory: testHistoryRoot)
    testPasteboard.clearContents()
    testPasteboard.setString("剪贴板测试文本", forType: .string)
    testHistory.captureCurrentPasteboardForTesting()
    expect(testHistory.entries.first?.kind == .text, "记录文本剪贴板")
    expect(testHistory.entries.first?.translatableText == "剪贴板测试文本", "文本剪贴板支持快速翻译")

    testPasteboard.clearContents()
    let linkItem = NSPasteboardItem()
    linkItem.setString("https://example.com/path", forType: .string)
    linkItem.setString("https://example.com/path", forType: .URL)
    testPasteboard.writeObjects([linkItem])
    testHistory.captureCurrentPasteboardForTesting()
    expect(testHistory.entries.first?.kind == .link, "记录链接剪贴板")

    let testImage = NSImage(size: NSSize(width: 8, height: 8))
    testImage.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 8, height: 8).fill()
    testImage.unlockFocus()
    testPasteboard.clearContents()
    testPasteboard.writeObjects([testImage])
    testHistory.captureCurrentPasteboardForTesting()
    expect(testHistory.entries.first?.kind == .image, "记录图片剪贴板")
    if let imageEntry = testHistory.entries.first {
        expect(testHistory.imageURL(for: imageEntry) != nil, "提供图片预览文件")
    }

    let testFile = testHistoryRoot.appendingPathComponent("文件测试.txt")
    try? FileManager.default.createDirectory(at: testHistoryRoot, withIntermediateDirectories: true)
    try? Data("file".utf8).write(to: testFile)
    testPasteboard.clearContents()
    let fileItem = NSPasteboardItem()
    fileItem.setString(testFile.absoluteString, forType: .fileURL)
    testPasteboard.writeObjects([fileItem])
    testHistory.captureCurrentPasteboardForTesting()
    expect(testHistory.entries.first?.kind == .files, "记录文件位置剪贴板")
    expect(testHistory.restoreToPasteboard(testHistory.entries[0]), "恢复文件剪贴板")
    try? FileManager.default.removeItem(at: testHistoryRoot)
    expect(
        WebSearch.googleURL(for: "划词 AI 测试")?.absoluteString ==
            "https://www.google.com/search?q=%E5%88%92%E8%AF%8D%20AI%20%E6%B5%8B%E8%AF%95",
        "生成 Google 搜索地址"
    )

    print(failures == 0 ? "SELF-TEST OK" : "SELF-TEST FAILED: \(failures)")
    exit(failures == 0 ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
