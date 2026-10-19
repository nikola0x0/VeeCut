import Foundation

private final class BundledResourceToken {}

enum BundledResource {
    // `swift run` places the bundle beside the executable; tests place it beside the `.xctest`.
    static let bundle: Bundle = {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return .main }
        let buildDirectories = [
            Bundle.main.resourceURL,
            Bundle(for: BundledResourceToken.self).bundleURL.deletingLastPathComponent(),
        ].compactMap { $0 }
        return buildDirectories.lazy
            .compactMap { Bundle(url: $0.appendingPathComponent("PalmierPro_PalmierPro.bundle")) }
            .first ?? .main
    }()

    // `resourceURL` resolves both flat (native SwiftPM) and `Contents/Resources` (Swift Build) layouts.
    static func url(_ path: String) -> URL? {
        guard let url = bundle.resourceURL?.appendingPathComponent(path),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
