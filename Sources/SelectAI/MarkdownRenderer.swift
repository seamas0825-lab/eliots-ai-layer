import AppKit

enum MarkdownRenderer {
    private static let bodyFont = NSFont.systemFont(ofSize: 14)

    static func render(_ markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var index = 0
        var codeLines: [String]? = nil

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if let buffered = codeLines {
                    appendCode(buffered.joined(separator: "\n"), to: output)
                    codeLines = nil
                } else {
                    codeLines = []
                }
                index += 1
                continue
            }

            if codeLines != nil {
                codeLines?.append(line)
                index += 1
                continue
            }

            if trimmed.isEmpty {
                appendBlankLine(to: output)
                index += 1
                continue
            }

            if let levelAndText = heading(from: trimmed) {
                appendHeading(levelAndText.text, level: levelAndText.level, to: output)
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                appendHorizontalRule(to: output)
                index += 1
                continue
            }

            if index + 1 < lines.count, looksLikeTableRow(line), isTableSeparator(lines[index + 1]) {
                let header = tableCells(line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count, looksLikeTableRow(lines[index]) {
                    rows.append(tableCells(lines[index]))
                    index += 1
                }
                appendTable(header: header, rows: rows, to: output)
                continue
            }

            if let item = unorderedListItem(from: line) {
                appendListItem("•", text: item, to: output)
                index += 1
                continue
            }

            if let item = orderedListItem(from: line) {
                appendListItem("\(item.number).", text: item.text, to: output)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                let quote = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                appendQuote(quote, to: output)
                index += 1
                continue
            }

            appendParagraph(line, to: output)
            index += 1
        }

        if let buffered = codeLines { appendCode(buffered.joined(separator: "\n"), to: output) }
        trimTrailingNewlines(in: output)
        detectPlainLinks(in: output)
        return output
    }

    private static func appendParagraph(_ text: String, to output: NSMutableAttributedString) {
        let style = paragraphStyle(spacing: 8)
        appendInline(text, font: bodyFont, color: .labelColor, style: style, to: output)
    }

    private static func appendHeading(_ text: String, level: Int, to output: NSMutableAttributedString) {
        let sizes: [CGFloat] = [21, 18, 16, 15, 14.5, 14]
        let size = sizes[min(max(level - 1, 0), sizes.count - 1)]
        let style = paragraphStyle(spacing: level <= 2 ? 10 : 7, spacingBefore: level <= 2 ? 7 : 4)
        appendInline(
            text,
            font: .systemFont(ofSize: size, weight: level <= 3 ? .semibold : .medium),
            color: .labelColor,
            style: style,
            to: output
        )
    }

    private static func appendListItem(
        _ marker: String,
        text: String,
        to output: NSMutableAttributedString
    ) {
        let style = paragraphStyle(spacing: 4)
        style.firstLineHeadIndent = 4
        style.headIndent = 24
        style.tabStops = [NSTextTab(textAlignment: .left, location: 24)]
        appendInline("\(marker)\t\(text)", font: bodyFont, color: .labelColor, style: style, to: output)
    }

    private static func appendQuote(_ text: String, to output: NSMutableAttributedString) {
        let style = paragraphStyle(spacing: 7)
        style.firstLineHeadIndent = 8
        style.headIndent = 20
        appendInline("▎ \(text)", font: bodyFont, color: .secondaryLabelColor, style: style, to: output)
        let range = NSRange(location: max(0, output.length - (text as NSString).length - 4), length: min(1, output.length))
        if range.length > 0 { output.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range) }
    }

    private static func appendCode(_ code: String, to output: NSMutableAttributedString) {
        let value = code.isEmpty ? " " : code
        let style = paragraphStyle(spacing: 9, spacingBefore: 4)
        style.firstLineHeadIndent = 10
        style.headIndent = 10
        style.tailIndent = -10
        let attributed = NSMutableAttributedString(
            string: value,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.16),
                .paragraphStyle: style
            ]
        )
        output.append(attributed)
        output.append(NSAttributedString(string: "\n"))
    }

    private static func appendTable(header: [String], rows: [[String]], to output: NSMutableAttributedString) {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return }
        let style = paragraphStyle(spacing: 3, spacingBefore: 4)
        style.tabStops = (1..<columnCount).map {
            NSTextTab(textAlignment: .left, location: CGFloat($0) * 150)
        }
        appendInline(
            paddedRow(header, count: columnCount),
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .labelColor,
            style: style,
            to: output
        )
        for row in rows {
            appendInline(
                paddedRow(row, count: columnCount),
                font: .systemFont(ofSize: 13),
                color: .labelColor,
                style: style,
                to: output
            )
        }
    }

    private static func appendHorizontalRule(to output: NSMutableAttributedString) {
        let style = paragraphStyle(spacing: 8, spacingBefore: 4)
        let line = NSAttributedString(
            string: "────────────────────────\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.separatorColor,
                .paragraphStyle: style
            ]
        )
        output.append(line)
    }

    private static func appendBlankLine(to output: NSMutableAttributedString) {
        guard output.length > 0, !output.string.hasSuffix("\n\n") else { return }
        output.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
    }

    private static func appendInline(
        _ markdown: String,
        font: NSFont,
        color: NSColor,
        style: NSParagraphStyle,
        to output: NSMutableAttributedString
    ) {
        let parsed: NSMutableAttributedString
        if let value = try? AttributedString(
            markdown: markdown,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            parsed = NSMutableAttributedString(attributedString: NSAttributedString(value))
        } else {
            parsed = NSMutableAttributedString(string: markdown)
        }

        let full = NSRange(location: 0, length: parsed.length)
        parsed.addAttributes([.font: font, .foregroundColor: color, .paragraphStyle: style], range: full)
        parsed.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
            guard let raw = (value as? NSNumber)?.uintValue else { return }
            if raw & InlinePresentationIntent.code.rawValue != 0 {
                parsed.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: max(11, font.pointSize - 0.5), weight: .regular),
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
                ], range: range)
            } else {
                var traits: NSFontTraitMask = []
                if raw & InlinePresentationIntent.stronglyEmphasized.rawValue != 0 { traits.insert(.boldFontMask) }
                if raw & InlinePresentationIntent.emphasized.rawValue != 0 { traits.insert(.italicFontMask) }
                if !traits.isEmpty {
                    parsed.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: traits), range: range)
                }
            }
            if raw & InlinePresentationIntent.strikethrough.rawValue != 0 {
                parsed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        parsed.enumerateAttribute(.link, in: full) { value, range, _ in
            guard value != nil else { return }
            parsed.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: range)
        }
        parsed.removeAttribute(.inlinePresentationIntent, range: full)
        output.append(parsed)
        output.append(NSAttributedString(string: "\n"))
    }

    private static func paragraphStyle(
        spacing: CGFloat,
        spacingBefore: CGFloat = 0
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.16
        style.paragraphSpacing = spacing
        style.paragraphSpacingBefore = spacingBefore
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let count = line.prefix { $0 == "#" }.count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }

    private static func unorderedListItem(from line: String) -> String? {
        capture(line, pattern: #"^\s*[-+*]\s+(.+)$"#, group: 1)
    }

    private static func orderedListItem(from line: String) -> (number: String, text: String)? {
        guard let match = firstMatch(line, pattern: #"^\s*(\d+)[.)]\s+(.+)$"#),
              let numberRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[numberRange]), String(line[textRange]))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, ["-", "*", "_"].contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func looksLikeTableRow(_ line: String) -> Bool {
        line.contains("|") && tableCells(line).count >= 2
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(line)
        return cells.count >= 2 && cells.allSatisfy {
            let value = $0.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            return value.count >= 3 && value.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func paddedRow(_ row: [String], count: Int) -> String {
        (0..<count).map { $0 < row.count ? row[$0] : "" }.joined(separator: "\t")
    }

    private static func capture(_ input: String, pattern: String, group: Int) -> String? {
        guard let match = firstMatch(input, pattern: pattern),
              let range = Range(match.range(at: group), in: input) else { return nil }
        return String(input[range])
    }

    private static func firstMatch(_ input: String, pattern: String) -> NSTextCheckingResult? {
        try? NSRegularExpression(pattern: pattern)
            .firstMatch(in: input, range: NSRange(input.startIndex..., in: input))
    }

    private static func trimTrailingNewlines(in output: NSMutableAttributedString) {
        while output.length > 0, output.string.hasSuffix("\n") {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
    }

    private static func detectPlainLinks(in output: NSMutableAttributedString) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let full = NSRange(location: 0, length: output.length)
        detector.enumerateMatches(in: output.string, range: full) { match, _, _ in
            guard let match, let url = match.url,
                  output.attribute(.link, at: match.range.location, effectiveRange: nil) == nil else { return }
            output.addAttributes([
                .link: url,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: match.range)
        }
    }
}
