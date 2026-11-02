import AppKit
import SwiftUI

/// A drawing of Vee from the app bundle, read and decoded off the main thread.
struct VeeIllustration: View {
    enum Name: String, CaseIterable, Sendable {
        case hello, vlogging, planning, listening, celebrating, oops, avatar
        case footageBox = "footage-box"
        case tourWelcome = "tour-welcome", tourPointUp = "tour-point-up", tourChat = "tour-chat", tourSwitch = "tour-switch"
        case tourFootage = "tour-footage", tourCamera = "tour-camera", tourTimeline = "tour-timeline", tourTune = "tour-tune", tourDone = "tour-done"
    }

    let name: Name
    let height: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .task(id: name) {
            image = await Self.data(for: name).flatMap(NSImage.init(data:))
        }
    }

    nonisolated static func data(for name: Name) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            BundledResource.url("Images/Vee/\(name.rawValue).png").flatMap { try? Data(contentsOf: $0) }
        }.value
    }
}
