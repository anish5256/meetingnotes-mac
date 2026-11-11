import SwiftUI
import AppKit

enum MeetingTextTab: Sendable, Equatable {
    case summary, transcript
}

struct MeetingText: Sendable {
    var summary = ""
    var transcript = ""
    var english = ""
    var error: String?

    func copyText(for tab: MeetingTextTab, showEnglish: Bool = false) -> String {
        switch tab {
        case .summary: return summary
        case .transcript: return showEnglish ? english : transcript
        }
    }

    static func load(_ folder: URL) -> MeetingText {
        func read(_ name: String) -> String? {
            try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        }
        let summary = read("summary.md")
        let transcript = read("transcript.corrected.txt") ?? read("transcript.hinglish.txt")
        return MeetingText(summary: summary ?? "", transcript: transcript ?? "",
                           english: read("transcript.english.txt") ?? "",
                           error: summary == nil || transcript == nil ? "Some meeting files could not be read." : nil)
    }
}

// Builders have no view state or side effects. Keep semantic colors dynamic for appearance changes.
enum MeetingAttributedText {
    static func transcript(_ source: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let body = NSFont.preferredFont(forTextStyle: .body)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let lines = source.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n\n")) }
            let row = NSMutableAttributedString(string: line, attributes: [
                .font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
            ])
            if line.hasPrefix("["), let end = line.firstIndex(of: "]") {
                let timestamp = NSRange(line.startIndex...end, in: line)
                row.addAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                                   .font: NSFont.monospacedDigitSystemFont(ofSize: body.pointSize, weight: .regular)], range: timestamp)
                let rest = line[line.index(after: end)...]
                let speakerStart = rest.firstIndex(where: { !$0.isWhitespace })
                if let start = speakerStart, line[start...].hasPrefix("Speaker "),
                   let colon = line[start...].firstIndex(of: ":") {
                    row.addAttribute(.font, value: NSFont.systemFont(ofSize: body.pointSize, weight: .semibold),
                                     range: NSRange(start..<colon, in: line))
                }
            }
            result.append(row)
        }
        return result
    }

    static func summary(_ source: String) -> NSAttributedString {
        var blocks: [String] = []
        var paragraph: [String] = []
        var seenContent = false
        func flush() {
            if !paragraph.isEmpty { blocks.append(paragraph.joined(separator: " ")); paragraph.removeAll() }
        }
        for line in source.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush(); continue }
            if !seenContent {
                seenContent = true
                if line.hasPrefix("# ") { continue }
            }
            if line.hasPrefix("## ") || line.hasPrefix("- ") { flush(); blocks.append(line) }
            else { paragraph.append(line) }
        }
        flush()
        let result = NSMutableAttributedString(string: "")
        for (index, block) in blocks.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n\n")) }
            let heading = block.hasPrefix("## ")
            let checkbox = block.hasPrefix("- [ ] ")
            let bullet = block.hasPrefix("- ")
            let text: String
            if heading { text = String(block.dropFirst(3)) }
            else if checkbox { text = "☐ " + block.dropFirst(6) }
            else if bullet { text = "• " + block.dropFirst(2) }
            else { text = block }
            let font = NSFont.preferredFont(forTextStyle: heading ? .title3 : .body)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            if bullet {
                let prefix = checkbox ? "☐ " : "• "
                style.headIndent = (prefix as NSString).size(withAttributes: [.font: font]).width
            }
            result.append(inlineBold(text, font: font, bold: heading, paragraph: style))
        }
        return result
    }

    private static func inlineBold(_ text: String, font: NSFont, bold: Bool,
                                   paragraph: NSParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        var remainder = text[...]
        func append(_ value: Substring, emphasized: Bool) {
            let resolved = emphasized ? NSFont.systemFont(ofSize: font.pointSize, weight: .bold) : font
            result.append(NSAttributedString(string: String(value), attributes: [
                .font: resolved, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
            ]))
        }
        while let opening = remainder.range(of: "**"),
              let closing = remainder[opening.upperBound...].range(of: "**") {
            append(remainder[..<opening.lowerBound], emphasized: bold)
            append(remainder[opening.upperBound..<closing.lowerBound], emphasized: true)
            remainder = remainder[closing.upperBound...]
        }
        append(remainder, emphasized: bold)
        return result
    }
}

struct SummaryTextView: View {
    let source: String
    var body: some View { MeetingDocumentView(source: source, tab: .summary) }
}

struct TranscriptTextView: View {
    let source: String
    var body: some View { MeetingDocumentView(source: source, tab: .transcript) }
}

private struct MeetingDocumentView: NSViewRepresentable {
    let source: String
    let tab: MeetingTextTab

    final class Coordinator {
        var source: String?
        var tab: MeetingTextTab?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let text = NSTextView(frame: .zero)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.importsGraphics = false
        text.usesFindBar = true
        text.isIncrementalSearchingEnabled = true
        text.drawsBackground = false
        text.textColor = .labelColor
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard context.coordinator.source != source || context.coordinator.tab != tab,
              let text = scroll.documentView as? NSTextView else { return }
        context.coordinator.source = source
        context.coordinator.tab = tab
        let attributed = tab == .summary ? MeetingAttributedText.summary(source) : MeetingAttributedText.transcript(source)
        if source.isEmpty {
            text.textStorage?.setAttributedString(NSAttributedString(
                string: tab == .summary ? "No summary available." : "No transcript available.",
                attributes: [.font: NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.secondaryLabelColor]))
        } else {
            text.textStorage?.setAttributedString(attributed)
        }
        text.setSelectedRange(NSRange(location: 0, length: 0))
        // Scroll to the top only after layout; scrolling before it finishes left long text opened at the end.
        func scrollToTop() {
            if let container = text.textContainer { text.layoutManager?.ensureLayout(for: container) }
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        scrollToTop()
        DispatchQueue.main.async { scrollToTop() }   // first appearance: the view gets its final size a pass later
    }
}

struct MeetingCopyActions {
    var transcript: () -> Void
    var summary: () -> Void
}

private struct MeetingCopyActionsKey: FocusedValueKey {
    typealias Value = MeetingCopyActions
}

extension FocusedValues {
    var meetingCopyActions: MeetingCopyActions? {
        get { self[MeetingCopyActionsKey.self] }
        set { self[MeetingCopyActionsKey.self] = newValue }
    }
}
