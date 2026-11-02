import AppKit
import SwiftUI

/// VeeCut's interface icons, from Phosphor Bold (MIT); the raw value is the file name in Images/Icons/Phosphor.
enum PhosphorIcon: String, CaseIterable, Sendable {
    case undo = "arrow-u-up-left"
    case redo = "arrow-u-up-right"
    case pointer = "cursor"
    case razor = "scissors"
    case trim = "arrows-horizontal"
    case split = "square-split-horizontal"
    case sparkle
    case timelines = "stack"
    case zoomOut = "magnifying-glass-minus"
    case zoomIn = "magnifying-glass-plus"
    case sidebar = "sidebar-simple"
    case export
    case history = "clock-counter-clockwise"
    case scribble
    case brush = "paint-brush"
    case search = "magnifying-glass"
    case selection
    case folder = "folder-simple"
    case list = "list-bullets"
    case subtitles
    case waveform
    case textAlignLeft = "text-align-left"
    case diamond
    case filmSlate = "film-slate"
    case sliders = "sliders-horizontal"
    case userFocus = "user-focus"
    case grid = "squares-four"
    case grip = "dots-six"
    case music = "music-notes"

    nonisolated static func data(for icon: PhosphorIcon) async -> Data? {
        await Task.detached(priority: .userInitiated) { fileData(icon) }.value
    }

    /// Reads the file synchronously; call off the main thread.
    nonisolated static func fileData(_ icon: PhosphorIcon) -> Data? {
        BundledResource.url("Images/Icons/Phosphor/\(icon.rawValue).svg").flatMap { try? Data(contentsOf: $0) }
    }
}

/// The icons read once, off the main thread, and kept as template images so they take the surrounding color.
@MainActor @Observable
final class IconLibrary {
    static let shared = IconLibrary()
    private(set) var images: [PhosphorIcon: NSImage] = [:]
    @ObservationIgnored private var loading: Task<Void, Never>?

    func load() async {
        if loading == nil {
            loading = Task {
                let files = await Task.detached(priority: .userInitiated) {
                    PhosphorIcon.allCases.map { ($0, PhosphorIcon.fileData($0)) }
                }.value
                var images: [PhosphorIcon: NSImage] = [:]
                for (icon, data) in files {
                    guard let data, let image = NSImage(data: data) else {
                        Log.app.error("icon missing name=\(icon.rawValue)")
                        continue
                    }
                    image.isTemplate = true
                    images[icon] = image
                }
                self.images = images
            }
        }
        await loading?.value
    }
}

/// A Phosphor icon filling its frame, tinted by the foreground style.
struct PhosphorImage: View {
    let icon: PhosphorIcon

    init(_ icon: PhosphorIcon) {
        self.icon = icon
    }

    var body: some View {
        Group {
            if let image = IconLibrary.shared.images[icon] {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
        .task { await IconLibrary.shared.load() }
    }
}
