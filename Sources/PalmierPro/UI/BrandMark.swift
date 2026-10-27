import SwiftUI

/// The VeeCut heart-play glyph, traced from `Resources/Images/veecut-logo.svg` (30-unit canvas).
private struct VeeCutGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 30
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: p(4.70922, 22.1224))
        path.addCurve(to: p(13.0239, 25.8935), control1: p(6.13831, 25.1951), control2: p(9.8626, 26.9177))
        path.addCurve(to: p(26.0157, 15.1388), control1: p(14.6262, 25.3814), control2: p(26.0157, 15.9768))
        path.addCurve(to: p(13.6735, 4.66344), control1: p(26.0157, 14.487), control2: p(15.3191, 5.3618))
        path.addCurve(to: p(8.3469, 4.66344), control1: p(11.7681, 3.77886), control2: p(10.3823, 3.77886))
        path.addCurve(to: p(4.31947, 9.17948), control1: p(6.13831, 5.6877), control2: p(4.83914, 7.08441))
        path.addCurve(to: p(4.75253, 13.0437), control1: p(3.97302, 10.6693), control2: p(4.05963, 11.3211))
        path.addCurve(to: p(4.75253, 16.9545), control1: p(5.57533, 15.0922), control2: p(5.57533, 15.1388))
        path.addCurve(to: p(4.70922, 22.1224), control1: p(3.75649, 19.1893), control2: p(3.75649, 20.0273))
        path.closeSubpath()
        return path
    }
}

struct VeeCutLogoMark: View {
    var size: CGFloat = AppTheme.IconSize.smMd

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * AppTheme.Brand.markCornerRatio, style: .continuous)
                .fill(Color(AppTheme.Palette.periwinkle))
            VeeCutGlyph()
                .fill(Color(AppTheme.Palette.blush))
                .shadow(
                    color: .black.opacity(AppTheme.Opacity.moderate),
                    radius: 0,
                    x: size * AppTheme.Brand.glyphShadowRatio,
                    y: 0
                )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct VeeCutWordmark: View {
    var markSize: CGFloat = AppTheme.IconSize.smMd
    var fontSize: CGFloat = AppTheme.FontSize.lg

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            VeeCutLogoMark(size: markSize)
            Text(verbatim: AppIdentity.name)
                .font(.custom(AppTheme.Brand.wordmarkFontName, size: fontSize).weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: AppIdentity.name))
    }
}
