import SwiftUI

/// Vee's current line as a subtitle over the preview, with its actions underneath; drag Vee's face or the grip and it settles at the nearest border spot.
struct VeeLineView: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var position = VeeLinePlacement.saved()
    @State private var bubbleSize: CGSize = .zero
    @State private var isHovering = false
    @GestureState(resetTransaction: Transaction(animation: AppTheme.Anim.fluid)) private var dragTranslation: CGSize = .zero
    private static let area = "veeLineArea"

    var body: some View {
        let line = editor.veeLine
        GeometryReader { geometry in
            if let line {
                let resting = VeeLinePlacement.center(for: position, bubble: bubbleSize, in: geometry.size)
                bubble(line, drag: drag(from: resting, in: geometry.size))
                    .onGeometryChange(for: CGSize.self, of: \.size) { bubbleSize = $0 }
                    .position(clampedCenter(resting, moved: dragTranslation, in: geometry.size))
                    .id(line.id)
                    .transition(.opacity)
            }
        }
        .coordinateSpace(.named(Self.area))
        .animation(.easeInOut(duration: AppTheme.Anim.transition), value: line?.id)
    }

    private func clampedCenter(_ resting: CGPoint, moved translation: CGSize, in container: CGSize) -> CGPoint {
        let raw = CGPoint(x: resting.x + translation.width, y: resting.y + translation.height)
        return VeeLinePlacement.center(for: VeeLinePlacement.position(for: raw, bubble: bubbleSize, in: container), bubble: bubbleSize, in: container)
    }

    private func drag(from resting: CGPoint, in container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: AppTheme.Spacing.sm, coordinateSpace: .named(Self.area))
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                let dropped = clampedCenter(resting, moved: value.translation, in: container)
                let spot = VeeLinePlacement.snapped(VeeLinePlacement.position(for: dropped, bubble: bubbleSize, in: container))
                withAnimation(AppTheme.Anim.fluid) { position = spot }
                VeeLinePlacement.save(spot)
            }
    }

    private func bubble(_ line: VeeLine, drag: some Gesture) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.mdLg) {
                VeeIllustration(name: line.pose, height: AppTheme.Coach.veeAvatarSize)
                    .frame(width: AppTheme.Coach.veeAvatarSize)
                    .dragHandle(drag, isDragging: dragTranslation != .zero)
                Text(line.text)
                    .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.FontSize.xl).weight(AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(Array(line.actions.enumerated()), id: \.element.id) { index, action in
                    button(action, isProminent: index == 0)
                }
            }
            .padding(.leading, AppTheme.Coach.veeAvatarSize + AppTheme.Spacing.mdLg)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.mdLg)
        .frame(maxWidth: AppTheme.Coach.subtitleMaxWidth, alignment: .leading)
        .padding(.trailing, AppTheme.Spacing.lg)
        .background(AppTheme.Coach.subtitleBackground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(alignment: .topTrailing) {
            PhosphorImage(.grip)
                .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
                .foregroundStyle(AppTheme.MediaOverlay.primaryColor.opacity(isHovering || dragTranslation != .zero ? AppTheme.Opacity.prominent : AppTheme.Opacity.muted))
                .padding(AppTheme.Spacing.sm)
                .dragHandle(drag, isDragging: dragTranslation != .zero)
        }
        .shadow(AppTheme.Shadow.md)
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: AppTheme.Anim.hover), value: isHovering)
    }

    private func button(_ action: VeeAction, isProminent: Bool) -> some View {
        Button {
            editor.perform(action)
        } label: {
            Text(verbatim: action.title)
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(isProminent ? AppTheme.Tint.inkColor : AppTheme.MediaOverlay.primaryColor)
                .padding(.horizontal, AppTheme.Spacing.mdLg)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(Capsule().fill(isProminent ? AppTheme.Tint.lilacColor : AppTheme.MediaOverlay.primaryColor.opacity(AppTheme.Opacity.muted)))
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    /// The parts of Vee's bubble that move it; the rest stays clickable.
    func dragHandle(_ drag: some Gesture, isDragging: Bool) -> some View {
        contentShape(Rectangle())
            .gesture(drag)
            .pointerStyle(isDragging ? .grabActive : .grabIdle)
            .help(L10n.string("Drag to move Vee"))
    }
}
