import AppKit
import SwiftUI

struct ProviderLogo: View {
    let iconKey: String
    var size: CGFloat = AppTheme.IconSize.sm

    private static let images: [String: NSImage] = {
        guard let directory = BundledResource.url("Images/LabLogos"),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else { return [:] }

        return Dictionary(uniqueKeysWithValues: urls.compactMap { url in
            let filename = url.deletingPathExtension().lastPathComponent
            guard ["png", "svg"].contains(url.pathExtension),
                  filename.hasPrefix("logo-"),
                  let image = NSImage(contentsOf: url) else { return nil }
            image.size = NSSize(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
            let key = String(filename.dropFirst("logo-".count))
            image.isTemplate = monochrome.contains(key)
            return (key, image)
        })
    }()

    /// Single-colour brand marks, drawn in the text colour so they read in light and dark mode.
    private static let monochrome: Set<String> = ["anthropic", "openai"]

    static func hasBundledLogo(for iconKey: String) -> Bool {
        images[iconKey] != nil
    }

    var body: some View {
        Group {
            if let image = Self.images[iconKey] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(AppTheme.Text.primaryColor)
            } else {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous))
        .accessibilityHidden(true)
    }
}
