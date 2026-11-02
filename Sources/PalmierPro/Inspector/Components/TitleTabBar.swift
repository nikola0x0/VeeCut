import SwiftUI

struct TitleTabBar: View {
    struct Item: Identifiable {
        let titleKey: String
        let icon: PhosphorIcon

        var id: String { titleKey }
    }

    let items: [Item]
    let selected: String?
    let onSelect: (String) -> Void

    /// Icon beside its name; a panel too narrow for the names shows icons only, named on hover.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsTitles: true)
            row(showsTitles: false)
        }
        .panelHeaderBar()
    }

    private func row(showsTitles: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.zero) {
            ForEach(items) { item in
                tab(item, showsTitle: showsTitles)
            }
        }
    }

    private func tab(_ item: Item, showsTitle: Bool) -> some View {
        let active = selected == item.id
        return Button {
            onSelect(item.id)
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                PhosphorImage(item.icon)
                    .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
                if showsTitle {
                    Text(L10n.string(key: item.titleKey))
                        .font(.system(
                            size: AppTheme.FontSize.sm,
                            weight: active ? AppTheme.FontWeight.semibold : AppTheme.FontWeight.medium
                        ))
                        .fixedSize()
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .lineLimit(1)
            .foregroundStyle(active ? AppTheme.Text.primaryColor : AppTheme.Text.tertiaryColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(active ? AppTheme.Text.primaryColor : Color.clear)
                    .frame(height: AppTheme.BorderWidth.thin)
                    .offset(y: -AppTheme.BorderWidth.thin)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(showsTitle ? "" : L10n.string(key: item.titleKey))
        .accessibilityLabel(L10n.string(key: item.titleKey))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
