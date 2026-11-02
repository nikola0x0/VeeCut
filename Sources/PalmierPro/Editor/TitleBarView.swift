import SwiftUI

struct TitleBarLeadingView: View {
    @Environment(EditorViewModel.self) var editor

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxs) {
            VeeCutWordmark()
                .padding(.trailing, AppTheme.Spacing.md)
            VeeButton()
                .padding(.trailing, AppTheme.Spacing.xs)
            PanelVisibilityButton(
                icon: .sidebar,
                label: L10n.string("Media Panel"),
                isVisible: editor.mediaPanelVisible
            ) {
                editor.mediaPanelVisible.toggle()
            }
            PanelVisibilityButton(
                icon: .sidebar,
                mirrored: true,
                label: L10n.string("Inspector Panel"),
                isVisible: editor.inspectorPanelVisible
            ) {
                editor.inspectorPanelVisible.toggle()
            }
        }
    }
}

struct TitleBarTrailingView: View {
    @Environment(EditorViewModel.self) var editor
    @State private var exportQueue = ExportQueue.shared

    var body: some View {
        let jobs = exportQueue.jobs(for: editor.exportQueueProjectID)
        let activeCount = jobs.count { $0.status.isRunning }
        let waitingCount = jobs.count { $0.status == .waiting }

        HStack(spacing: AppTheme.Spacing.sm) {
            Spacer(minLength: AppTheme.Spacing.zero)

            Picker(L10n.string("Editor Mode"), selection: Binding(get: { editor.editorMode }, set: { editor.setEditorMode($0) })) {
                Text(L10n.string("Simple")).tag(EditorMode.simple)
                Text(L10n.string("Pro")).tag(EditorMode.pro)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(L10n.string("Simple shows the essentials; Pro shows every tool"))
            .tourAnchor(.editorModeSwitch)

            UndoHistoryButton()

            Button(action: { editor.showExportDialog = true }) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if activeCount > 0 {
                        exportActivityDot
                    } else {
                        PhosphorImage(.export)
                            .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
                    }
                    Text(L10n.string("Export"))
                }
                .titlebarCapsule(
                    fill: AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.muted),
                    foreground: AppTheme.Text.secondaryColor
                )
            }
            .buttonStyle(.plain)
            .help(L10n.string("Export (⌘E)"))
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(
                activeCount == 0 && waitingCount == 0
                    ? L10n.string("Export")
                    : L10n.string("Export, \(activeCount) active, \(waitingCount) waiting")
            )
        }
    }

    private var exportActivityDot: some View {
        PhaseAnimator([false, true]) { dimmed in
            Circle()
                .fill(AppTheme.Status.warningColor)
                .frame(width: AppTheme.Export.activityDotSize, height: AppTheme.Export.activityDotSize)
                .opacity(dimmed ? AppTheme.Opacity.medium : AppTheme.Opacity.opaque)
        } animation: { _ in
            .easeInOut(duration: AppTheme.Anim.pulse)
        }
        .accessibilityHidden(true)
    }
}

/// Vee's face in the title bar; opens and closes the chat with Vee, and hops when it opens.
private struct VeeButton: View {
    @Environment(EditorViewModel.self) private var editor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hops = 0

    private struct Hop {
        var lift: CGFloat = 0
        var tilt: Double = 0
        var scale: CGFloat = 1
        var ring: Double = 0
    }

    var body: some View {
        let isOpen = editor.agentPanelVisible
        Button { editor.agentPanelVisible.toggle() } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                avatar
                Text(L10n.string("Vee"))
                    .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.FontSize.md).weight(AppTheme.FontWeight.semibold))
            }
            .padding(.leading, AppTheme.Spacing.xxs)
            .padding(.trailing, AppTheme.Spacing.smMd)
            .frame(height: AppTheme.IconSize.lg)
            .foregroundStyle(isOpen ? AppTheme.Tint.inkColor : AppTheme.Text.primaryColor)
            .background(Capsule().fill(isOpen ? AppTheme.Tint.lilacColor : AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.muted)))
            .animation(.easeOut(duration: AppTheme.Anim.transition), value: isOpen)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .help(L10n.string("Talk to Vee (\u{2325}\u{2318}A)"))
        .tourAnchor(.veeButton)
        .onChange(of: isOpen) { _, open in
            if open, !reduceMotion { hops += 1 }
        }
    }

    private var avatar: some View {
        VeeIllustration(name: .avatar, height: AppTheme.IconSize.md)
            .frame(width: AppTheme.IconSize.md)
            .keyframeAnimator(initialValue: Hop(), trigger: hops) { content, hop in
                content
                    .background {
                        Circle()
                            .stroke(AppTheme.Tint.lilacColor, lineWidth: AppTheme.BorderWidth.thick)
                            .scaleEffect(1 + hop.ring)
                            .opacity(hop.ring > 0 ? 1 - hop.ring : 0)
                    }
                    .scaleEffect(hop.scale)
                    .rotationEffect(.degrees(hop.tilt))
                    .offset(y: -hop.lift)
            } keyframes: { _ in
                let d = AppTheme.Anim.veeHop
                SwiftUI.KeyframeTrack(\Hop.lift) {
                    CubicKeyframe(AppTheme.Spacing.sm, duration: d * 0.35)
                    SpringKeyframe(CGFloat.zero, duration: d * 0.65, spring: Spring.bouncy)
                }
                SwiftUI.KeyframeTrack(\Hop.tilt) {
                    CubicKeyframe(-12, duration: d * 0.2)
                    CubicKeyframe(10, duration: d * 0.25)
                    CubicKeyframe(-5, duration: d * 0.2)
                    CubicKeyframe(0, duration: d * 0.35)
                }
                SwiftUI.KeyframeTrack(\Hop.scale) {
                    CubicKeyframe(CGFloat(1.18), duration: d * 0.35)
                    SpringKeyframe(CGFloat(1), duration: d * 0.65, spring: Spring.bouncy)
                }
                SwiftUI.KeyframeTrack(\Hop.ring) {
                    LinearKeyframe(0.01, duration: 0.01)
                    CubicKeyframe(0.9, duration: d)
                    LinearKeyframe(0, duration: 0.01)
                }
            }
    }
}

private struct PanelVisibilityButton: View {
    let icon: PhosphorIcon
    var mirrored = false
    let label: String
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PhosphorImage(icon)
                .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
                .scaleEffect(x: mirrored ? -1 : 1)
                .foregroundStyle(isVisible ? AppTheme.Text.primaryColor : AppTheme.Text.mutedColor)
                .frame(width: AppTheme.IconSize.lg, height: AppTheme.IconSize.lg)
                .hoverHighlight()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isVisible ? .isSelected : [])
        .help(label)
    }
}
