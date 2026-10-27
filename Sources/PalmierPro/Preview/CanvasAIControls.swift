import SwiftUI

/// Canvas tools on the preview's leading edge.
struct CanvasToolPalette: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Button {
                editor.toggleSubjectSelection()
            } label: {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                    .frame(width: AppTheme.IconSize.mdLg, height: AppTheme.IconSize.mdLg)
                    .foregroundStyle(editor.subjectSelectionActive ? AppTheme.MediaOverlay.primaryColor : AppTheme.MediaOverlay.secondaryColor)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .fill(editor.subjectSelectionActive ? AppTheme.Accent.canvasAI : AppTheme.Background.clearColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(editor.isSubjectTracking)
            .help(L10n.string("Select Subject — drag a box or click on what to track"))
        }
        .padding(AppTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(AppTheme.MediaOverlay.backgroundColor.opacity(AppTheme.Opacity.high))
        )
        .padding(.leading, AppTheme.Spacing.smMd)
    }
}

/// Floating bar over the preview: tracking progress, failures, then one-click looks.
struct SubjectActionBar: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        Group {
            if let clipId = editor.subjectTrackingClipId {
                trackingRow(progress: editor.objectTrackingProgress[clipId] ?? 0)
            } else if let failure = editor.subjectTrackingFailure {
                failureRow(failure)
            } else if editor.canvasSubject != nil {
                looksRow
            } else if editor.subjectSelectionActive {
                hint(L10n.string("Drag a box around the subject, or click it"))
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

    private var looksRow: some View {
        capsule {
            barButton(L10n.string("Pop Subject"), prominent: true) { editor.applySubjectLook(.popSubject) }
            barButton(L10n.string("Darken Background"), prominent: true) { editor.applySubjectLook(.darkenBackground) }
            barButton(L10n.string("Blur Background"), prominent: true) { editor.applySubjectLook(.blurBackground) }
            Button { editor.canvasSubject = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.MediaOverlay.secondaryColor)
            }
            .buttonStyle(.plain)
            .help(L10n.string("Done"))
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
        case .notFound: L10n.string("No subject found there. Try a tighter box.")
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

    private func barButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
                .padding(.horizontal, AppTheme.Spacing.smMd)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(Capsule().fill(prominent ? AppTheme.Accent.canvasAI : AppTheme.MediaOverlay.primaryColor.opacity(AppTheme.Opacity.muted)))
        }
        .buttonStyle(.plain)
    }
}
