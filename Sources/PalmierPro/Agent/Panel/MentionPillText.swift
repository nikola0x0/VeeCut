import SwiftUI

extension AgentMention {
    /// Pill colors: the object's kind color for picked objects, neutral for media, clips and ranges.
    var pillStyle: (fill: Color, text: Color) {
        object == nil
            ? (AppTheme.ObjectKind.neutralPill, AppTheme.ObjectKind.neutralPillText)
            : (AppTheme.ObjectKind.pill, AppTheme.ObjectKind.pillText)
    }

    /// The pill's label: the display name without "@", padded so the rounded background has room.
    var pillLabel: String { "\u{2009}\(displayName)\u{2009}" }
}

/// Marks a run of text to be drawn on a rounded pill.
struct MentionPillAttribute: TextAttribute {
    let fill: Color
}

/// Draws a rounded background behind runs carrying `MentionPillAttribute`.
struct MentionPillRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if let pill = run[MentionPillAttribute.self] {
                    let rect = run.typographicBounds.rect.insetBy(dx: 0, dy: -AppTheme.Spacing.xxs)
                    context.fill(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous).path(in: rect),
                        with: .color(pill.fill)
                    )
                }
                context.draw(run)
            }
        }
    }
}

/// Chat text with registered mentions drawn as pills.
func mentionPillText(_ text: String, mentions: [AgentMention]) -> Text {
    MentionSegments.split(text, mentions: mentions).reduce(Text(verbatim: "")) { result, segment in
        switch segment {
        case .text(let plain):
            return joined(result, Text(verbatim: plain))
        case .mention(let mention):
            let style = mention.pillStyle
            let pill = Text(verbatim: mention.pillLabel)
                .fontWeight(.semibold)
                .foregroundStyle(style.text)
                .customAttribute(MentionPillAttribute(fill: style.fill))
            return joined(result, pill)
        }
    }
}

/// Concatenates styled texts without the deprecated `+`; the "%@%@" key is pure formatting.
private func joined(_ first: Text, _ second: Text) -> Text {
    Text("\(first)\(second)")
}
