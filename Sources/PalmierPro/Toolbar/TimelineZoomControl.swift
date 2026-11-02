import SwiftUI

/// Zoom out, a log-mapped slider and zoom in; shared by both toolbars.
struct TimelineZoomControl: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            zoomButton(
                .zoomOut,
                help: L10n.string("Zoom Out"),
                isDisabled: editor.zoomScale <= editor.minZoomScale,
                action: zoomOut
            )
            // Log-mapped so slider travel is uniform per zoom factor
            let zoomBinding = Binding(
                get: { log(editor.zoomScale) },
                set: { editor.zoomScale = exp($0) }
            )
            Slider(value: zoomBinding, in: log(editor.minZoomScale)...log(Zoom.max))
                .controlSize(.mini)
                .tint(AppTheme.Accent.primary)
                .frame(width: 100)
            zoomButton(
                .zoomIn,
                help: L10n.string("Zoom In"),
                isDisabled: editor.zoomScale >= Zoom.max,
                tooltipAlignment: .bottomTrailing,
                action: zoomIn
            )
        }
    }

    private func zoomButton(
        _ icon: PhosphorIcon,
        help: String,
        isDisabled: Bool,
        tooltipAlignment: Alignment = .bottom,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            PhosphorImage(icon)
                .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
                .foregroundStyle(isDisabled ? AppTheme.Text.mutedColor : AppTheme.Text.tertiaryColor)
                .frame(width: AppTheme.IconSize.mdLg, height: AppTheme.IconSize.mdLg)
                .hoverHighlight()
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .hoverTooltip(help, alignment: tooltipAlignment)
    }

    private func zoomOut() {
        setZoomScale(editor.zoomScale / Zoom.toolbarStepFactor)
    }

    private func zoomIn() {
        setZoomScale(editor.zoomScale * Zoom.toolbarStepFactor)
    }

    private func setZoomScale(_ zoomScale: Double) {
        editor.zoomScale = min(Zoom.max, max(editor.minZoomScale, zoomScale))
    }
}
