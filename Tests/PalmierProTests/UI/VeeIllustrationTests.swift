import AppKit
import Testing
@testable import PalmierPro

struct VeeIllustrationTests {
    @Test(arguments: VeeIllustration.Name.allCases)
    func everyIllustrationShipsWithTheApp(_ name: VeeIllustration.Name) async throws {
        let data = try #require(await VeeIllustration.data(for: name))
        #expect(NSImage(data: data) != nil)
    }
}
