import SwiftUI

struct AudioPanelTab: View {
    @State private var silenceExpanded = true

    var body: some View {
        ScrollView {
            SpeechAnalysisSections(silenceExpanded: $silenceExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Background.surfaceColor)
    }
}
