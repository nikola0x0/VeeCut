import Testing
@testable import PalmierPro

@Test(arguments: [
    "Vignette.metallib",
    "Fonts",
    "Images/LabLogos",
    "Images/Vee/hello.png",
    "Changelog/changelog.json",
    "Models/BeatThis.mlmodelc",
    "veecut.mcpb",
])
func bundledResourceResolvesInBuiltResourceBundle(path: String) {
    #expect(BundledResource.url(path) != nil)
}

@Test func bundledResourceRejectsMissingPath() {
    #expect(BundledResource.url("Missing/does-not-exist.bin") == nil)
}
