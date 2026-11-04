import Testing
@testable import PalmierPro

@Test(arguments: [AppTheme.BorderWidth.thin, AppTheme.BorderWidth.focus])
func outlineWidthsAreWholePointsSoEveryEdgeDrawsEvenlyOnA1xDisplay(width: Double) {
    #expect(width == width.rounded())
}
