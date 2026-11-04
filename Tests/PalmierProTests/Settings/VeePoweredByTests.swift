import Testing
@testable import PalmierPro

@Test(arguments: [
    ("sk-ant-abc", "sk-ant-abc"),
    ("  sk-abc \n", "sk-abc"),
    ("   ", nil),
    ("", nil),
] as [(String, String?)])
func aPastedKeyIsTrimmedAndBlankIsRefused(draft: String, saved: String?) {
    #expect(VeePoweredBy.keyToSave(draft) == saved)
}

@Test(arguments: [
    ("sk-ant-abcd1234", "\u{2022}\u{2022}\u{2022}\u{2022}1234"),
    ("abc", "\u{2022}\u{2022}\u{2022}\u{2022}"),
])
func aSavedKeyShowsOnlyItsLastFour(key: String, shown: String) {
    #expect(VeePoweredBy.masked(key) == shown)
}
