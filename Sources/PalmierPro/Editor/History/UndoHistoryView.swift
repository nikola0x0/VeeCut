import SwiftUI

/// Title bar button that opens the edit history.
struct UndoHistoryButton: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            PhosphorImage(.history)
                .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
                .foregroundStyle(isPresented ? AppTheme.Text.primaryColor : AppTheme.Text.secondaryColor)
                .frame(width: AppTheme.IconSize.lg, height: AppTheme.IconSize.lg)
                .hoverHighlight(isActive: isPresented)
        }
        .buttonStyle(.plain)
        .help(L10n.string("Edit History"))
        .accessibilityLabel(L10n.string("Edit History"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            UndoHistoryList(undo: editor.undo)
        }
    }
}

/// Every editor action, newest first, including ones saved in earlier sessions. Click a row to return to the moment after it.
struct UndoHistoryList: View {
    let undo: EditorUndo

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            HStack {
                Text(L10n.string("Edit History"))
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                Spacer(minLength: AppTheme.Spacing.zero)
                Text(L10n.string("\(undo.historyPosition) of \(undo.history.count)"))
                    .font(.system(size: AppTheme.FontSize.xs).monospacedDigit())
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            .padding(AppTheme.Spacing.mdLg)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    ForEach(Array(undo.history.enumerated()).reversed(), id: \.element.id) { index, entry in
                        row(
                            title: entry.actionName,
                            date: entry.date,
                            position: index + 1
                        )
                    }
                    row(title: L10n.string("Start of history"), date: nil, position: 0)
                }
                .padding(AppTheme.Spacing.sm)
            }
        }
        .frame(width: AppTheme.History.listWidth, height: AppTheme.History.listHeight)
    }

    private func row(title: String, date: Date?, position: Int) -> some View {
        let isCurrent = position == undo.historyPosition
        let isUndone = position > undo.historyPosition
        return Button { undo.jump(toHistoryPosition: position) } label: {
            HStack(spacing: AppTheme.Spacing.smMd) {
                Circle()
                    .fill(isCurrent ? AppTheme.Accent.primary : AppTheme.Text.mutedColor.opacity(isUndone ? AppTheme.Opacity.medium : AppTheme.Opacity.opaque))
                    .frame(width: AppTheme.ComponentSize.timelineDotSize, height: AppTheme.ComponentSize.timelineDotSize)
                Text(verbatim: title)
                    .font(.system(size: AppTheme.FontSize.sm, weight: isCurrent ? AppTheme.FontWeight.semibold : AppTheme.FontWeight.regular))
                    .foregroundStyle(isUndone ? AppTheme.Text.mutedColor : AppTheme.Text.primaryColor)
                    .strikethrough(isUndone, color: AppTheme.Text.mutedColor)
                    .lineLimit(1)
                Spacer(minLength: AppTheme.Spacing.sm)
                if let date {
                    Text(date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.smMd)
            .frame(height: AppTheme.EditorPanel.groupHeaderHeight)
            .hoverHighlight(isActive: isCurrent)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Brief note on the preview naming the action ⌘Z or ⇧⌘Z just moved past.
struct UndoStepToast: View {
    let undo: EditorUndo
    @State private var visibleStep: UndoStepEvent?

    var body: some View {
        Group {
            if let step = visibleStep {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: step.direction == .undo ? "arrow.uturn.backward" : "arrow.uturn.forward")
                    Text(step.direction == .undo
                         ? L10n.string("Undo: \(step.actionName)")
                         : L10n.string("Redo: \(step.actionName)"))
                    Text(L10n.string("Step \(step.position) of \(step.count)"))
                        .foregroundStyle(AppTheme.MediaOverlay.tertiaryColor)
                        .monospacedDigit()
                }
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
                .padding(.horizontal, AppTheme.Spacing.mdLg)
                .padding(.vertical, AppTheme.Spacing.smMd)
                .background(Capsule().fill(AppTheme.MediaOverlay.backgroundColor.opacity(AppTheme.Opacity.prominent)))
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, AppTheme.Spacing.lgXl)
        .animation(.easeOut(duration: AppTheme.Anim.hover), value: visibleStep)
        .allowsHitTesting(false)
        .task(id: undo.lastStep?.id) {
            guard let step = undo.lastStep else { return }
            visibleStep = step
            try? await Task.sleep(for: AppTheme.History.toastDuration)
            if visibleStep == step { visibleStep = nil }
        }
    }
}
