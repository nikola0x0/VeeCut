import SwiftUI

/// Canvas tools on the preview's leading edge.
struct CanvasToolPalette: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            toolButton(.subject, systemImage: "person.crop.rectangle",
                       help: L10n.string("Select Subject — scribble over, circle, or click what to track"))
            toolButton(.area, systemImage: "square.dashed",
                       help: L10n.string("Draw Area — drag a rectangle or draw a loop around a part of the frame"))
        }
        .padding(AppTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(AppTheme.MediaOverlay.backgroundColor.opacity(AppTheme.Opacity.high))
        )
        .padding(.leading, AppTheme.Spacing.smMd)
    }

    private func toolButton(_ kind: CanvasSelectionKind, systemImage: String, help: String) -> some View {
        let active = editor.canvasSelection == kind
        return Button {
            editor.toggleCanvasSelection(kind)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                .frame(width: AppTheme.IconSize.mdLg, height: AppTheme.IconSize.mdLg)
                .foregroundStyle(active ? AppTheme.MediaOverlay.primaryColor : AppTheme.MediaOverlay.secondaryColor)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(active ? AppTheme.Accent.canvasAI : AppTheme.Background.clearColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(editor.isSubjectTracking)
        .help(help)
    }
}

/// Floating bar over the preview: selection hint, tracking progress and failures.
struct SubjectActionBar: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        Group {
            if let clipId = editor.subjectTrackingClipId {
                trackingRow(progress: editor.objectTrackingProgress[clipId] ?? 0)
            } else if let failure = editor.subjectTrackingFailure {
                failureRow(failure)
            } else if let subject = editor.canvasSubject {
                trackedRow(isArea: editor.trackedMask(id: subject.maskId)?.isDrawnArea == true)
            } else if let kind = editor.canvasSelection {
                switch kind {
                case .subject: hint(L10n.string("Scribble over the subject, circle it, or click it"))
                case .area: hint(L10n.string("Drag a rectangle, or draw a loop around the area"))
                }
            }
        }
        .padding(.bottom, AppTheme.Spacing.lgXl)
    }

    private func trackingRow(progress: Double) -> some View {
        capsule {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(AppTheme.Accent.canvasAI)
                .frame(width: AppTheme.ComponentSize.projectCardWidth)
            Text(L10n.string("Tracking subject…"))
                .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
            barButton(L10n.string("Cancel")) { _ = editor.cancelSubjectInteraction() }
        }
    }

    private func failureRow(_ failure: SubjectTrackingFailure) -> some View {
        capsule {
            Text(message(for: failure))
                .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
            barButton(L10n.string("Dismiss")) { _ = editor.cancelSubjectInteraction() }
        }
    }

    private func trackedRow(isArea: Bool) -> some View {
        capsule {
            Text(isArea
                ? L10n.string("Area added. Add looks in the Subject inspector.")
                : L10n.string("Subject tracked. Add looks in the Subject inspector."))
                .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
            barButton(L10n.string("Done")) { editor.canvasSubject = nil }
        }
    }

    private func hint(_ text: String) -> some View {
        capsule {
            Text(verbatim: text).foregroundStyle(AppTheme.MediaOverlay.secondaryColor)
        }
    }

    private func message(for failure: SubjectTrackingFailure) -> String {
        switch failure {
        case .missingAPIKey: L10n.string("Add a Meta Model API key in Settings to track subjects.")
        case .notFound: L10n.string("No subject found there. Try scribbling right on it.")
        case .modelFailed: L10n.string("SAM couldn't follow that spot. Scribble across more of the subject, or try another frame.")
        case .failed: L10n.string("Tracking failed. Try again.")
        }
    }

    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: AppTheme.Spacing.smMd) { content() }
            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
            .padding(.horizontal, AppTheme.Spacing.mdLg)
            .padding(.vertical, AppTheme.Spacing.smMd)
            .background(Capsule().fill(AppTheme.MediaOverlay.backgroundColor.opacity(AppTheme.Opacity.prominent)))
            .shadow(AppTheme.Shadow.md)
    }

    private func barButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
                .padding(.horizontal, AppTheme.Spacing.smMd)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(Capsule().fill(AppTheme.MediaOverlay.primaryColor.opacity(AppTheme.Opacity.muted)))
        }
        .buttonStyle(.plain)
    }
}
