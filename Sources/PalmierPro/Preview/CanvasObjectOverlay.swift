import SwiftUI

/// Where a canvas object sits on the preview at the playhead.
@MainActor
enum CanvasObjectGeometry {
    /// The object's box in view points, or the clip's own box for the whole clip. Nil while it is off screen.
    static func viewRect(of subject: CanvasSubject, in viewSize: CGSize, editor: EditorViewModel) -> CGRect? {
        let frame = editor.activeFrame
        guard let clip = editor.clipFor(id: subject.clipId), clip.contains(timelineFrame: frame) else { return nil }
        let box = if let maskId = subject.maskId {
            editor.subjectBox(of: maskId, in: clip, at: frame)
        } else {
            editor.canvasBox(ofSource: CGRect(x: 0, y: 0, width: 1, height: 1), in: clip, at: frame)
        }
        guard let box else { return nil }
        let videoRect = PreviewHitTester.videoContentRect(in: viewSize, timeline: editor.timeline)
        return CGRect(
            x: videoRect.minX + box.minX * videoRect.width, y: videoRect.minY + box.minY * videoRect.height,
            width: box.width * videoRect.width, height: box.height * videoRect.height
        )
    }
}

/// Tints the selected object and the one a shelf chip hovers.
struct CanvasObjectHighlights: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        ZStack {
            ForEach(highlighted, id: \.self) { subject in
                if let maskId = subject.maskId {
                    SubjectMaskOverlayView(clipId: subject.clipId, maskId: maskId)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var highlighted: [CanvasSubject] {
        var subjects: [CanvasSubject] = []
        if let selected = editor.validCanvasSubject { subjects.append(selected) }
        if let hovered = editor.hoveredObject, !subjects.contains(hovered) { subjects.append(hovered) }
        return subjects
    }
}

/// Name tags pinned to the selected and hovered objects, kept inside the preview.
struct CanvasObjectOverlay: View {
    @Environment(EditorViewModel.self) private var editor

    private static let tagHeight = AppTheme.IconSize.mdLg

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let selected = editor.validCanvasSubject
            ZStack(alignment: .topLeading) {
                if let hovered = editor.hoveredObject, hovered != selected,
                   let rect = CanvasObjectGeometry.viewRect(of: hovered, in: size, editor: editor) {
                    ObjectNameTag(subject: hovered, isSelected: false)
                        .offset(tagOffset(rect, in: size))
                        .allowsHitTesting(false)
                }
                if let selected, selected.maskId != nil,
                   let rect = CanvasObjectGeometry.viewRect(of: selected, in: size, editor: editor) {
                    ObjectNameTag(subject: selected, isSelected: true)
                        .offset(tagOffset(rect, in: size))
                }
            }
        }
    }

    private func tagOffset(_ rect: CGRect, in size: CGSize) -> CGSize {
        let x = min(max(rect.minX, 0), max(0, size.width - AppTheme.ComponentSize.objectTagMaxWidth))
        let above = rect.minY - Self.tagHeight - AppTheme.Spacing.xs
        return CGSize(width: x, height: above >= 0 ? above : max(0, rect.minY) + AppTheme.Spacing.xs)
    }
}

/// The object's name pinned to it; clicking the selected object's tag renames it in place.
private struct ObjectNameTag: View {
    @Environment(EditorViewModel.self) private var editor
    let subject: CanvasSubject
    let isSelected: Bool
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if let maskId = subject.maskId, let mask = editor.trackedMask(id: maskId) {
            Group {
                if isSelected, editor.renamingObjectId == maskId {
                    TextField(String(), text: $draft)
                        .textFieldStyle(.plain)
                        .frame(width: AppTheme.ComponentSize.timelineTabRenameWidth)
                        .focused($focused)
                        .onAppear {
                            draft = mask.label
                            focused = true
                        }
                        .onSubmit { commit(maskId) }
                        .onExitCommand { editor.renamingObjectId = nil }
                        .onChange(of: focused) { _, isFocused in if !isFocused { commit(maskId) } }
                        .accessibilityLabel(L10n.string("Object name"))
                } else {
                    Text(verbatim: mask.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
            .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
            .padding(.horizontal, AppTheme.Spacing.smMd)
            .frame(height: AppTheme.IconSize.mdLg)
            .background(Capsule(style: .continuous).fill(
                isSelected ? AppTheme.Accent.canvasAI : AppTheme.MediaOverlay.backgroundColor.opacity(AppTheme.Opacity.prominent)
            ))
            .shadow(AppTheme.Shadow.md)
            .contentShape(Capsule())
            .onTapGesture { if isSelected { editor.renamingObjectId = maskId } }
            .help(isSelected ? L10n.string("Click to rename") : String())
            .frame(width: AppTheme.ComponentSize.objectTagMaxWidth, alignment: .leading)
        }
    }

    private func commit(_ maskId: String) {
        guard editor.renamingObjectId == maskId else { return }
        editor.renamingObjectId = nil
        editor.renameSubject(maskId: maskId, to: draft)
    }
}
