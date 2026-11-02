import AppKit
import SwiftUI

/// The chat input: plain text with registered mentions shown as pills. The binding stays a plain `@Name` string,
/// and each pill is one attachment character, so Backspace removes it whole.
struct MentionTextView: NSViewRepresentable {
    enum Command {
        case moveUp, moveDown, submit, newline, tab, backtab, cancel
    }

    @Binding var text: String
    let mentions: [AgentMention]
    @Binding var isFocused: Bool
    let onCommand: (Command) -> Bool
    /// Handles file and image pastes; returns false to paste the clipboard as plain text.
    let onPaste: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PillTextView()
        textView.coordinator = context.coordinator
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Coordinator.font
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        let clipView = TopAnchoredClipView()
        clipView.drawsBackground = false
        let scrollView = NSScrollView()
        scrollView.contentView = clipView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.render(text, mentions: mentions)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if text != coordinator.lastText || mentions != coordinator.lastMentions {
            coordinator.render(text, mentions: mentions)
        }
        guard let textView = coordinator.textView else { return }
        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    /// Measures with TextKit 2; asking a TextKit 2 view for `layoutManager` returns a stand-in that measures nothing.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = context.coordinator.textView,
              let layout = textView.textLayoutManager, let container = layout.textContainer else { return nil }
        let width = proposal.width ?? nsView.frame.width
        container.size = NSSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: layout.documentRange)
        let content = ceil(max(layout.usageBoundsForTextContainer.height, Coordinator.font.boundingRectForFont.height))
        return CGSize(width: width, height: min(max(content, AppTheme.Composer.minTextHeight), AppTheme.Composer.maxTextHeight))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        static let font = NSFont.preferredFont(forTextStyle: .body)

        var parent: MentionTextView
        weak var textView: PillTextView?
        private(set) var lastText = ""
        private(set) var lastMentions: [AgentMention] = []
        private var isRendering = false

        init(_ parent: MentionTextView) {
            self.parent = parent
        }

        private var baseAttributes: [NSAttributedString.Key: Any] {
            [.font: Self.font, .foregroundColor: NSColor.labelColor]
        }

        /// Rebuilds the storage from the draft; the caret goes to the end, where mentions are inserted.
        func render(_ text: String, mentions: [AgentMention]) {
            guard let textView, let storage = textView.textStorage else { return }
            isRendering = true
            defer { isRendering = false }
            let rendered = NSMutableAttributedString()
            for segment in MentionSegments.split(text, mentions: mentions) {
                switch segment {
                case .text(let plain):
                    rendered.append(NSAttributedString(string: plain, attributes: baseAttributes))
                case .mention(let mention):
                    let pill = NSMutableAttributedString(attachment: MentionPillAttachment(mention: mention, font: Self.font))
                    pill.addAttributes(baseAttributes, range: NSRange(location: 0, length: pill.length))
                    rendered.append(pill)
                }
            }
            storage.setAttributedString(rendered)
            textView.typingAttributes = baseAttributes
            textView.setSelectedRange(NSRange(location: rendered.length, length: 0))
            lastText = text
            lastMentions = mentions
        }

        private func serializedText() -> String {
            guard let storage = textView?.textStorage else { return "" }
            var result = ""
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if let pill = value as? MentionPillAttachment {
                    result += "@\(pill.mention.displayName)"
                } else {
                    result += storage.attributedSubstring(from: range).string.replacingOccurrences(of: "\u{FFFC}", with: "")
                }
            }
            return result
        }

        func textDidChange(_ notification: Notification) {
            guard !isRendering else { return }
            let text = serializedText()
            lastText = text
            parent.text = text
        }

        func focusChanged(_ focused: Bool) {
            guard parent.isFocused != focused else { return }
            parent.isFocused = focused
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let command: Command? = switch selector {
            case #selector(NSResponder.moveUp(_:)): .moveUp
            case #selector(NSResponder.moveDown(_:)): .moveDown
            case #selector(NSResponder.insertNewline(_:)):
                NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? .newline : .submit
            case #selector(NSResponder.insertTab(_:)): .tab
            case #selector(NSResponder.insertBacktab(_:)): .backtab
            // Escape arrives as complete: in a text view, not cancelOperation:.
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)): .cancel
            default: nil
            }
            guard let command else { return false }
            return parent.onCommand(command)
        }

        func paste() -> Bool { parent.onPaste() }
    }
}

/// Keeps short text at the top of the input; the default clip view pins a shorter document to the bottom.
private final class TopAnchoredClipView: NSClipView {
    override var isFlipped: Bool { true }
}

final class PillTextView: NSTextView {
    weak var coordinator: MentionTextView.Coordinator?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { coordinator?.focusChanged(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { coordinator?.focusChanged(false) }
        return resigned
    }

    override func paste(_ sender: Any?) {
        if coordinator?.paste() != true { pasteAsPlainText(sender) }
    }
}

/// One mention drawn as a rounded pill sitting on the text baseline.
final class MentionPillAttachment: NSTextAttachment {
    let mention: AgentMention

    init(mention: AgentMention, font: NSFont) {
        self.mention = mention
        super.init(data: nil, ofType: nil)
        let style = mention.pillStyle
        let label = NSAttributedString(string: mention.displayName, attributes: [
            .font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: NSColor(style.text),
        ])
        let padding = AppTheme.Spacing.sm
        let size = NSSize(width: ceil(label.size().width) + padding * 2, height: ceil(font.ascender - font.descender) + AppTheme.Spacing.xxs * 2)
        let fill = NSColor(style.fill)
        image = NSImage(size: size, flipped: false) { rect in
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: AppTheme.Radius.sm, yRadius: AppTheme.Radius.sm).fill()
            label.draw(at: NSPoint(x: padding, y: (rect.height - label.size().height) / 2))
            return true
        }
        bounds = CGRect(x: 0, y: font.descender - AppTheme.Spacing.xxs, width: size.width, height: size.height)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
