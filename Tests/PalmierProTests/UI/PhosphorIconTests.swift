import AppKit
import Testing
@testable import PalmierPro

struct PhosphorIconTests {
    @Test(arguments: PhosphorIcon.allCases)
    func everyIconShipsWithTheApp(_ icon: PhosphorIcon) async throws {
        let data = try #require(await PhosphorIcon.data(for: icon))
        #expect(NSImage(data: data) != nil)
    }

    @MainActor @Test func theLibraryLoadsEveryIconAsATemplate() async {
        let library = IconLibrary()
        await library.load()
        #expect(library.images.count == PhosphorIcon.allCases.count)
        #expect(library.images.values.allSatisfy { $0.isTemplate })
    }
}
