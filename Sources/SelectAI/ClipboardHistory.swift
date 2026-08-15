import AppKit
import CryptoKit

enum ClipboardEntryKind: String, Codable {
    case text
    case link
    case image
    case files

    var displayName: String {
        switch self {
        case .text: return "文本"
        case .link: return "链接"
        case .image: return "图片"
        case .files: return "文件"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }
}

struct ClipboardEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: ClipboardEntryKind
    var text: String?
    var filePaths: [String]
    var imageFileName: String?
    var createdAt: Date
    var sourceBundleID: String?
    let fingerprint: String

    var title: String {
        switch kind {
        case .text:
            return Self.singleLine(text ?? "文本")
        case .link:
            return text ?? "链接"
        case .image:
            return "图片"
        case .files:
            let names = filePaths.prefix(3).map { URL(fileURLWithPath: $0).lastPathComponent }
            let suffix = filePaths.count > 3 ? " 等 \(filePaths.count) 个文件" : ""
            return names.joined(separator: "、") + suffix
        }
    }

    var translatableText: String? {
        guard kind == .text,
              let value = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func singleLine(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.count > 180 ? String(normalized.prefix(180)) + "…" : normalized
    }
}

final class ClipboardHistoryManager {
    var onChange: (([ClipboardEntry]) -> Void)?

    private(set) var entries: [ClipboardEntry] = []
    private let pasteboard: NSPasteboard
    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let imageDirectory: URL
    private let metadataURL: URL
    private var timer: Timer?
    private var lastChangeCount: Int
    private var isCaptureSuspended = false

    private struct Candidate {
        let kind: ClipboardEntryKind
        let text: String?
        let filePaths: [String]
        let imageData: Data?
        let fingerprint: String
        let sourceBundleID: String?
    }

    init(pasteboard: NSPasteboard = .general, rootDirectory customRoot: URL? = nil) {
        self.pasteboard = pasteboard
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootDirectory = customRoot
            ?? support.appendingPathComponent("SelectAI/ClipboardHistory", isDirectory: true)
        imageDirectory = rootDirectory.appendingPathComponent("Images", isDirectory: true)
        metadataURL = rootDirectory.appendingPathComponent("history.json")
        lastChangeCount = pasteboard.changeCount
        prepareStorage()
        load()
        trimToConfiguredLimit()
    }

    func captureCurrentPasteboardForTesting() {
        guard !shouldIgnoreCurrentPasteboard(), let candidate = candidateFromPasteboard() else { return }
        add(candidate)
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func suspendCapture() {
        isCaptureSuspended = true
    }

    func resumeCaptureAfterInternalChange() {
        lastChangeCount = pasteboard.changeCount
        isCaptureSuspended = false
    }

    func updateLimit() {
        trimToConfiguredLimit()
        persist()
        onChange?(entries)
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard let url = imageURL(for: entry) else { return nil }
        return NSImage(contentsOf: url)
    }

    func imageURL(for entry: ClipboardEntry) -> URL? {
        guard entry.kind == .image, let name = entry.imageFileName else { return nil }
        let url = imageDirectory.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func restoreToPasteboard(_ entry: ClipboardEntry) -> Bool {
        pasteboard.clearContents()
        let success: Bool

        switch entry.kind {
        case .text:
            success = pasteboard.setString(entry.text ?? "", forType: .string)
        case .link:
            let value = entry.text ?? ""
            let item = NSPasteboardItem()
            item.setString(value, forType: .string)
            item.setString(value, forType: .URL)
            success = pasteboard.writeObjects([item])
        case .image:
            guard let image = image(for: entry) else { return false }
            success = pasteboard.writeObjects([image])
        case .files:
            let items: [NSPasteboardItem] = entry.filePaths.compactMap { path in
                let url = URL(fileURLWithPath: path)
                guard fileManager.fileExists(atPath: url.path) else { return nil }
                let item = NSPasteboardItem()
                item.setString(url.absoluteString, forType: .fileURL)
                return item
            }
            guard !items.isEmpty else { return false }
            success = pasteboard.writeObjects(items)
        }

        lastChangeCount = pasteboard.changeCount
        if success { markUsed(entry) }
        return success
    }

    func delete(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        deleteImageIfNeeded(for: entry)
        persist()
        onChange?(entries)
    }

    func clear() {
        entries.forEach(deleteImageIfNeeded)
        entries.removeAll()
        persist()
        onChange?(entries)
    }

    private func checkForChanges() {
        guard !isCaptureSuspended else { return }
        guard AppSettings.clipboardHistoryEnabled else {
            lastChangeCount = pasteboard.changeCount
            return
        }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !shouldIgnoreCurrentPasteboard(), let candidate = candidateFromPasteboard() else { return }
        add(candidate)
    }

    private func shouldIgnoreCurrentPasteboard() -> Bool {
        let ignored = Set([
            "org.nspasteboard.TransientType",
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.AutoGeneratedType",
            "com.agilebits.onepassword",
            "com.typeit4me.clipping",
            "de.petermaurer.TransientPasteboardType",
            "net.antelle.keeweb"
        ])
        let currentTypes = Set((pasteboard.types ?? []).map(\.rawValue))
        return !ignored.isDisjoint(with: currentTypes)
    }

    private func candidateFromPasteboard() -> Candidate? {
        let items = pasteboard.pasteboardItems ?? []
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let filePaths = items.compactMap { item -> String? in
            guard let value = item.string(forType: .fileURL),
                  let url = URL(string: value), url.isFileURL else { return nil }
            return url.path
        }
        if !filePaths.isEmpty {
            let fingerprint = Self.hash(Data(("files:" + filePaths.joined(separator: "\u{1F}")) .utf8))
            return Candidate(
                kind: .files,
                text: nil,
                filePaths: filePaths,
                imageData: nil,
                fingerprint: fingerprint,
                sourceBundleID: sourceBundleID
            )
        }

        for item in items {
            if let rawImage = item.data(forType: .png) ?? item.data(forType: .tiff),
               let png = Self.pngData(from: rawImage) {
                return Candidate(
                    kind: .image,
                    text: nil,
                    filePaths: [],
                    imageData: png,
                    fingerprint: Self.hash(png),
                    sourceBundleID: sourceBundleID
                )
            }
        }

        let explicitURL = items.compactMap { $0.string(forType: .URL) }.first
        let string = items.compactMap { $0.string(forType: .string) }.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let link = explicitURL ?? string.flatMap(Self.webURLString)
        if let link, !link.isEmpty {
            return Candidate(
                kind: .link,
                text: link,
                filePaths: [],
                imageData: nil,
                fingerprint: Self.hash(Data(("link:" + link).utf8)),
                sourceBundleID: sourceBundleID
            )
        }

        guard let string, !string.isEmpty else { return nil }
        return Candidate(
            kind: .text,
            text: String(string.prefix(200_000)),
            filePaths: [],
            imageData: nil,
            fingerprint: Self.hash(Data(("text:" + string).utf8)),
            sourceBundleID: sourceBundleID
        )
    }

    private func add(_ candidate: Candidate) {
        if let index = entries.firstIndex(where: { $0.fingerprint == candidate.fingerprint }) {
            var existing = entries.remove(at: index)
            existing.createdAt = Date()
            existing.sourceBundleID = candidate.sourceBundleID
            entries.insert(existing, at: 0)
        } else {
            let id = UUID()
            var imageName: String?
            if let imageData = candidate.imageData {
                let name = "\(id.uuidString).png"
                do {
                    try imageData.write(to: imageDirectory.appendingPathComponent(name), options: .atomic)
                    imageName = name
                } catch {
                    return
                }
            }

            let entry = ClipboardEntry(
                id: id,
                kind: candidate.kind,
                text: candidate.text,
                filePaths: candidate.filePaths,
                imageFileName: imageName,
                createdAt: Date(),
                sourceBundleID: candidate.sourceBundleID,
                fingerprint: candidate.fingerprint
            )
            entries.insert(entry, at: 0)
        }

        trimToConfiguredLimit()
        persist()
        onChange?(entries)
    }

    private func markUsed(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var used = entries.remove(at: index)
        used.createdAt = Date()
        entries.insert(used, at: 0)
        persist()
        onChange?(entries)
    }

    private func trimToConfiguredLimit() {
        let limit = AppSettings.clipboardHistoryLimit
        guard entries.count > limit else { return }
        let removed = entries.suffix(from: limit)
        removed.forEach(deleteImageIfNeeded)
        entries = Array(entries.prefix(limit))
    }

    private func prepareStorage() {
        try? fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func deleteImageIfNeeded(for entry: ClipboardEntry) {
        guard let name = entry.imageFileName else { return }
        try? fileManager.removeItem(at: imageDirectory.appendingPathComponent(name))
    }

    private static func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func webURLString(_ value: String) -> String? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return value
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
