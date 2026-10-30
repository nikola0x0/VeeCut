import Foundation
import Testing
@testable import PalmierPro

@Suite("ProviderLogo")
@MainActor
struct ProviderLogoTests {
    @Test func bundlesOpenAILogo() {
        #expect(ProviderLogo.hasBundledLogo(for: "openai"))
    }

    @Test func unknownIconKeysFallBackSafely() {
        #expect(!ProviderLogo.hasBundledLogo(for: "new-provider"))
        #expect(!ProviderLogo.hasBundledLogo(for: "../openai"))
    }
}
