import SwiftUI

/// Moves the clip with a tracked object in a video clip under it, or stops following.
struct SubjectFollowRow: View {
    @Environment(EditorViewModel.self) private var editor
    let clip: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            menuRow
            if let link = clip.subjectFollow {
                InspectorRow(label: L10n.string("Spot")) {
                    FollowAnchorGrid(link: link) { editor.setFollowAnchor(clipId: clip.id, anchor: $0) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var menuRow: some View {
        let choices = editor.followableSubjects(for: clip.id)
        return InspectorRow(label: L10n.string("Follow")) {
            Menu {
                if choices.isEmpty {
                    Text(L10n.string("Track an object in the video under this clip first"))
                }
                ForEach(choices, id: \.subject) { choice in
                    Button {
                        if case .failure(let failure) = editor.followSubject(clipId: clip.id, subject: choice.subject) {
                            editor.subjectFollowFailure = failure
                        }
                    } label: {
                        Text(verbatim: choice.mask.label)
                    }
                }
                if clip.subjectFollow != nil {
                    Divider()
                    Button(L10n.string("Stop Following")) { editor.stopFollowing(clipId: clip.id) }
                }
            } label: {
                EditorMenuValue(text: followingName.map { L10n.string("Following \($0)") } ?? L10n.string("Choose an object"), expanded: true)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).focusable(false)
            .frame(maxWidth: .infinity)
            .help(L10n.string("Move this clip with a tracked object. Drag it on the canvas to change where it sits on the object."))
        }
    }

    private var followingName: String? {
        guard let link = clip.subjectFollow else { return nil }
        return editor.trackedMask(id: link.maskId)?.label ?? L10n.string("an object")
    }
}

/// Nine spots of the object's box: corners, edge midpoints and center. The clip's current spot is filled.
private struct FollowAnchorGrid: View {
    let link: SubjectFollowLink
    let onPick: (CGPoint) -> Void
    private static let steps: [Double] = [0, 0.5, 1]

    var body: some View {
        Grid(horizontalSpacing: AppTheme.Spacing.xxs, verticalSpacing: AppTheme.Spacing.xxs) {
            ForEach(Self.steps, id: \.self) { y in
                GridRow {
                    ForEach(Self.steps, id: \.self) { x in
                        dot(CGPoint(x: x, y: y))
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin)
        )
    }

    private func dot(_ anchor: CGPoint) -> some View {
        let selected = abs(link.anchorX - anchor.x) < 0.05 && abs(link.anchorY - anchor.y) < 0.05
        return Button { onPick(anchor) } label: {
            Circle()
                .fill(selected ? AppTheme.Accent.canvasAI : AppTheme.Interaction.fill(AppTheme.Opacity.muted))
                .frame(width: AppTheme.IconSize.xxs / 2, height: AppTheme.IconSize.xxs / 2)
                .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.string("Keep the clip at this spot of the object"))
    }
}
