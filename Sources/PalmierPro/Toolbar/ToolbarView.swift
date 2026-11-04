import AppKit
import SwiftUI

struct ToolbarView: View {
    @Environment(EditorViewModel.self) var editor

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            timelineTabsButton

            toolbarDivider

            HStack(spacing: AppTheme.Spacing.md) {
                toolbarButton(.undo, help: L10n.string("Undo (⌘Z)"), action: undo)
                toolbarButton(.redo, help: L10n.string("Redo (⇧⌘Z)"), action: redo)
            }

            toolbarDivider

            HStack(spacing: AppTheme.Spacing.md) {
                toolModeButton(.pointer, mode: .pointer, help: L10n.string("Pointer (V)"))
                toolModeButton(.razor, mode: .razor, help: L10n.string("Razor (C)"))
                toolModeButton(.trim, mode: .trim, help: L10n.string("Trim (T)"))
            }

            toolbarDivider

            HStack(spacing: AppTheme.Spacing.md) {
                toolbarButton(.split, help: L10n.string("Split at Playhead (⌘K)"), action: editor.splitAtPlayhead)
                bracketButton("[", help: L10n.string("Trim Start to Playhead (Q)"), action: editor.trimStartToPlayhead)
                bracketButton("]", help: L10n.string("Trim End to Playhead (W)"), action: editor.trimEndToPlayhead)
            }

            toolbarDivider

            HStack(spacing: AppTheme.Spacing.md) {
                textGlyphButton("T", help: L10n.string("Add Text"), action: { _ = editor.addTextClip() })
                markerButton
            }

            toolbarDivider

            toolbarButton(.sparkle, help: editor.planTheEditHelp, action: editor.askForPlan)
                .disabled(!editor.hasCoachFootage)

            Spacer()

            TimelineZoomControl()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity)
    }

    private var timelineTabsButton: some View {
        let expanded = editor.isTimelineTabBarExpanded
        return Button {
            editor.toggleTimelineTabBarExpanded()
        } label: {
            PhosphorImage(.timelines)
                .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
                .foregroundStyle(expanded ? AppTheme.Text.primaryColor : AppTheme.Text.tertiaryColor)
                .frame(width: AppTheme.IconSize.mdLg, height: AppTheme.IconSize.mdLg)
                .hoverHighlight(isActive: expanded)
        }
        .buttonStyle(.plain)
        .hoverTooltip(
            L10n.string(expanded ? "Hide Timeline Tabs" : "Show Timeline Tabs"),
            alignment: .bottomLeading
        )
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(AppTheme.Border.primaryColor)
            .frame(width: AppTheme.BorderWidth.thin, height: AppTheme.Spacing.xl)
    }

    private var markerButton: some View {
        HStack(spacing: AppTheme.Spacing.xxs) {
            Button { _ = editor.addTimelineMarkerAtSelection() } label: {
                TimelineMarkerShape()
                    .fill(AppTheme.Text.secondaryColor)
                    .frame(
                        width: AppTheme.TimelineMarker.flagWidth,
                        height: AppTheme.TimelineMarker.flagHeight
                    )
                    .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.mdLg)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("Add Marker (M)"))

            Menu {
                Toggle(
                    L10n.string("Ripple Timeline Markers"),
                    isOn: Bindable(editor).rippleTimelineMarkers
                )
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: AppTheme.FontSize.micro, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .frame(width: AppTheme.Spacing.md, height: AppTheme.IconSize.mdLg)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(L10n.string("Ripple Timeline Markers"))
        }
        .padding(.trailing, AppTheme.Spacing.xxs)
        .hoverHighlight()
        .hoverTooltip(L10n.string("Add Marker (M)"))
    }

    private func toolbarButton(_ icon: PhosphorIcon, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PhosphorImage(icon)
                .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .frame(width: AppTheme.IconSize.mdLg, height: AppTheme.IconSize.mdLg)
                .hoverHighlight()
        }
        .buttonStyle(.plain)
        .hoverTooltip(help)
    }

    private func undo() {
        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
    }

    private func redo() {
        NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
    }

    private func toolModeButton(_ icon: PhosphorIcon, mode: ToolMode, help: String) -> some View {
        let isActive = editor.toolMode == mode
        return Button { editor.toolMode = mode } label: {
            PhosphorImage(icon)
                .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
                .foregroundStyle(isActive ? AppTheme.Text.primaryColor : AppTheme.Text.tertiaryColor)
                .frame(width: AppTheme.IconSize.mdLg, height: AppTheme.IconSize.mdLg)
                .hoverHighlight(isActive: isActive)
        }
        .buttonStyle(.plain)
        .hoverTooltip(help)
    }

    private func textGlyphButton(_ glyph: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .frame(width: 24, height: 24)
                .hoverHighlight()
        }
        .buttonStyle(.plain)
        .hoverTooltip(help)
    }

    private func bracketButton(_ bracket: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(bracket)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .frame(width: 24, height: 24)
                .hoverHighlight()
        }
        .buttonStyle(.plain)
        .hoverTooltip(help)
    }
}
