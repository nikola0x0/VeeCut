import SwiftUI

/// The content of a chip: leading artwork, then the title. `sizedFor` keeps the chip as wide as its longest option.
struct ChipLabel<Artwork: View>: View {
    let title: String
    var sizedFor: [String] = []
    @ViewBuilder let artwork: Artwork

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            artwork
                .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
            ZStack(alignment: .leading) {
                ForEach(sizedFor, id: \.self) { option in
                    Text(verbatim: option).hidden()
                }
                Text(verbatim: title)
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
    }
}

extension View {
    /// A menu drawn as a tinted capsule chip.
    func chipMenu() -> some View {
        menuStyle(.button)
            .buttonStyle(.capsule(.tinted, size: .regular))
            .menuIndicator(.hidden)
            .fixedSize()
    }

    /// A text-entry surface: the base fill with a hairline border that turns accent while focused, as on Vee's card.
    func veeField(focused: Bool) -> some View {
        background(AppTheme.Background.baseColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .strokeBorder(focused ? AppTheme.Accent.primary : AppTheme.Border.primaryColor,
                                  lineWidth: focused ? AppTheme.BorderWidth.medium : AppTheme.BorderWidth.thin)
                    .allowsHitTesting(false)
            }
    }
}
