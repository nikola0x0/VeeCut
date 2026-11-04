import AppKit
import UniformTypeIdentifiers

/// Open Project's panel; picks `.veecut` packages by extension, so it works where macOS hasn't registered the document type (e.g. `swift run`).
@MainActor
enum ProjectOpenPanel {
    nonisolated static func isProject(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(Project.fileExtension) == .orderedSame
    }

    static func begin(_ completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        let delegate = Delegate()
        panel.delegate = delegate
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.string("Open Project")
        panel.begin { response in
            withExtendedLifetime(delegate) {}
            completion(response == .OK ? panel.url : nil)
        }
    }

    /// Folders stay enabled so you can browse into them; only a project passes Open.
    private final class Delegate: NSObject, NSOpenSavePanelDelegate {
        func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
            url.hasDirectoryPath || ProjectOpenPanel.isProject(url)
        }

        func panel(_ sender: Any, validate url: URL) throws {
            guard ProjectOpenPanel.isProject(url) else {
                throw CocoaError(.fileReadUnsupportedScheme, userInfo: [
                    NSLocalizedDescriptionKey: L10n.string("Choose a VeeCut project (.veecut)."),
                ])
            }
        }
    }
}
