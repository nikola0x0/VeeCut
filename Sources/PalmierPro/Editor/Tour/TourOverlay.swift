import AppKit
import SwiftUI

struct TourOverlay: View {
    @Environment(EditorViewModel.self) private var editor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tour: TourController { editor.tour }
    private let margin: CGFloat = AppTheme.Spacing.xlXxl

    private static let docsURL = URL(string: "https://github.com/nikola0x0/VeeCut#readme")!

    var body: some View {
        if let step = tour.currentStep {
            GeometryReader { geo in
                let frame = tour.targetFrame
                let isSpotlight = isSpotlightStep(step)
                ZStack(alignment: .topLeading) {
                    scrim(cutout: isSpotlight ? frame : nil)
                        .contentShape(Rectangle())
                        .onTapGesture { if isSpotlight { tour.end() } }

                    switch step.kind {
                    case .intro:
                        introCard(step)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    case .outro:
                        outroCard(step)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    case .spotlight:
                        if let frame {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                                .strokeBorder(AppTheme.Accent.spotlightGradient, lineWidth: AppTheme.BorderWidth.thick)
                                .frame(width: frame.width, height: frame.height)
                                .offset(x: frame.minX, y: frame.minY)
                                .shadow(color: AppTheme.Accent.spotlight.opacity(AppTheme.Opacity.strong), radius: 10)
                                .allowsHitTesting(false)
                        }
                        callout(step)
                            .position(calloutPosition(for: frame, in: geo.size))
                    }
                }
                .ignoresSafeArea()
            }
            .transition(.opacity)
        }
    }

    private func isSpotlightStep(_ step: TourStep) -> Bool {
        if case .spotlight = step.kind { return true }
        return false
    }

    private func scrim(cutout: CGRect?) -> some View {
        AppTheme.MediaOverlay.backgroundColor.opacity(AppTheme.Opacity.strong)
            .reverseMask {
                if let cutout {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                        .frame(width: cutout.width, height: cutout.height)
                        .offset(x: cutout.minX, y: cutout.minY)
                }
            }
    }

    // MARK: - Pieces

    /// Vee pops in with each new step.
    private func pose(_ step: TourStep, height: CGFloat) -> some View {
        VeeIllustration(name: step.pose, height: height)
            .id(tour.stepIndex)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6), value: tour.stepIndex)
    }

    private func title(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.custom(AppTheme.Brand.wordmarkFontName, size: size).weight(AppTheme.FontWeight.semibold))
            .foregroundStyle(AppTheme.Text.primaryColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.md))
            .foregroundStyle(AppTheme.Text.secondaryColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One dot per spotlight step; the current one is a wider accent pill.
    private var progressDots: some View {
        let current = (tour.stepIndex ?? 0) - 1
        return HStack(spacing: AppTheme.Spacing.xxs) {
            ForEach(0..<tour.spotlightCount, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AppTheme.Accent.primary : AppTheme.Text.mutedColor.opacity(AppTheme.Opacity.medium))
                    .frame(width: index == current ? AppTheme.Tour.activeDotWidth : AppTheme.Tour.dotSize, height: AppTheme.Tour.dotSize)
            }
        }
        .animation(.easeOut(duration: AppTheme.Anim.transition), value: current)
        .accessibilityElement()
        .accessibilityLabel(L10n.string("Step \(current + 1) of \(tour.spotlightCount)"))
    }

    // MARK: - Spotlight callout

    private func callout(_ step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                pose(step, height: AppTheme.Tour.calloutPoseHeight)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    title(step.title, size: AppTheme.FontSize.xl)
                    bodyText(step.instruction)
                }
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                progressDots
                Spacer(minLength: AppTheme.Spacing.sm)
                Button(L10n.string("Skip")) { tour.end() }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("Back")) { tour.back() }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                Button(L10n.string("Next")) { tour.advance() }
                    .buttonStyle(.capsule(.prominent, size: .regular))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: AppTheme.Tour.calloutWidth)
        .tourCard()
    }

    // MARK: - Intro / outro cards

    private func introCard(_ step: TourStep) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            pose(step, height: AppTheme.Tour.bookendPoseHeight)
            VStack(spacing: AppTheme.Spacing.sm) {
                title(step.title, size: AppTheme.FontSize.title2)
                bodyText(step.instruction)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: AppTheme.Spacing.sm) {
                Button(L10n.string("Maybe later")) { tour.end() }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("Show me around")) { tour.advance() }
                    .buttonStyle(.capsule(.prominent, size: .regular))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: AppTheme.Tour.bookendWidth)
        .tourCard()
    }

    private func outroCard(_ step: TourStep) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            pose(step, height: AppTheme.Tour.bookendPoseHeight)
            VStack(spacing: AppTheme.Spacing.sm) {
                title(step.title, size: AppTheme.FontSize.title2)
                bodyText(step.instruction)
            }
            .multilineTextAlignment(.center)
            VStack(spacing: 0) {
                linkRow(L10n.string("Add API keys in Settings"), "key.fill") { SettingsWindowController.shared.show() }
                linkRow(L10n.string("Keyboard Shortcuts"), "keyboard") { HelpWindowController.shared.show(tab: .shortcuts) }
                linkRow(L10n.string("Documentation"), "book.fill") { NSWorkspace.shared.open(Self.docsURL, configuration: .init(), completionHandler: nil) }
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                Button(L10n.string("Back")) { tour.back() }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                Button(L10n.string("Let's go!")) { tour.end() }
                    .buttonStyle(.capsule(.prominent, size: .regular))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: AppTheme.Tour.bookendWidth)
        .tourCard()
    }

    private func linkRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: AppTheme.FontSize.smMd))
                    .foregroundStyle(AppTheme.Accent.primary)
                    .frame(width: AppTheme.IconSize.sm)
                Text(title)
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }
            .padding(.vertical, AppTheme.Spacing.smMd)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Place the spotlight card adjacent to the highlighted region
    private func calloutPosition(for frame: CGRect?, in size: CGSize) -> CGPoint {
        guard let frame else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let cardWidth = AppTheme.Tour.calloutWidth
        let cardHeight = AppTheme.Tour.calloutHeightEstimate
        let neededX = cardWidth + margin * 2

        if size.width - frame.maxX > neededX {            // room to the right
            return CGPoint(x: frame.maxX + margin + cardWidth / 2, y: clampY(frame.midY, in: size))
        }
        if frame.minX > neededX {                         // room to the left
            return CGPoint(x: frame.minX - margin - cardWidth / 2, y: clampY(frame.midY, in: size))
        }
        let x = clampX(frame.midX, in: size)
        if frame.minY > cardHeight + margin * 2 {         // room above (sit just above the frame)
            return CGPoint(x: x, y: clampY(frame.minY - margin - cardHeight / 2, in: size))
        }
        return CGPoint(x: x, y: clampY(frame.maxY + margin + cardHeight / 2, in: size)) // else below
    }

    private func clampX(_ x: CGFloat, in size: CGSize) -> CGFloat {
        let half = AppTheme.Tour.calloutWidth / 2
        return min(max(x, half + margin), size.width - half - margin)
    }

    private func clampY(_ y: CGFloat, in size: CGSize) -> CGFloat {
        let half = AppTheme.Tour.calloutHeightEstimate / 2
        return min(max(y, half + margin), size.height - half - margin)
    }
}

// MARK: - Anchor tagging

extension View {
    /// Registers this view's backing `NSView` as a tour anchor, so the split
    /// controller can highlight it. Pair with a `TourStep` targeting `.element(id)`.
    func tourAnchor(_ id: TourAnchorID) -> some View {
        background(TourAnchorRegistrar(id: id))
    }
}

private struct TourAnchorRegistrar: NSViewRepresentable {
    let id: TourAnchorID
    @Environment(EditorViewModel.self) private var editor

    func makeNSView(context: Context) -> TourAnchorNSView {
        let view = TourAnchorNSView()
        // Recompute the highlight when this control appears/animates inside a panel.
        view.onLayout = { [weak editor] in
            guard let editor else { return }
            DispatchQueue.main.async { editor.tour.anchorDidLayout() }
        }
        editor.tour.anchorViews[id] = WeakView(view)
        return view
    }

    func updateNSView(_ nsView: TourAnchorNSView, context: Context) {
        if editor.tour.anchorViews[id]?.value !== nsView {
            editor.tour.anchorViews[id] = WeakView(nsView)
        }
    }
}

/// Invisible background view that reports when it lays out, so anchors that appear
/// or resize inside a panel trigger a fresh highlight-frame computation.
private final class TourAnchorNSView: NSView {
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
}

private extension View {
    func tourCard() -> some View {
        background(AppTheme.Background.raisedColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.xl).strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin))
            .shadow(AppTheme.Shadow.lg)
    }

    /// Punches the masked shapes out of `self` (inverse of `.mask`).
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: .topLeading) { mask().blendMode(.destinationOut) }
        }
        .compositingGroup()
    }
}
