import SwiftUI

/// Caption transcription progress on the panel's own colors: clips done of the total, the bar easing
/// through the clip in flight since transcription reports no finer progress.
struct TranscriptionProgressCard: View {
    let progress: (completed: Int, total: Int)?
    @State private var clipStarted = Date.now

    /// Within one clip the fill eases toward 90% of that clip's share.
    private static let estimateTimeConstant = 8.0
    private static let estimateCeiling = 0.9

    var body: some View {
        let completed = progress?.completed ?? 0
        let total = max(progress?.total ?? 1, 1)
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "waveform")
                    .foregroundStyle(AppTheme.Accent.canvasAI)
                Text(total > 1
                    ? L10n.string("Transcribing \(min(completed + 1, total)) of \(total) clips…")
                    : L10n.string("Transcribing…"))
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .monospacedDigit()
            }
            SwiftUI.TimelineView(.animation(minimumInterval: 0.1)) { context in
                let elapsed = max(context.date.timeIntervalSince(clipStarted), 0)
                let inFlight = completed < total ? Self.estimateCeiling * (1 - exp(-elapsed / Self.estimateTimeConstant)) : 0
                let fraction = (Double(completed) + inFlight) / Double(total)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.Interaction.fill(AppTheme.Opacity.faint))
                        Capsule()
                            .fill(AppTheme.Accent.canvasAI)
                            .frame(width: geometry.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: AppTheme.Spacing.sm)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: AppTheme.ComponentSize.transcriptionCardWidth)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous).fill(AppTheme.Background.raisedColor))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        )
        .shadow(AppTheme.Shadow.md)
        .onChange(of: progress?.completed) { _, _ in clipStarted = .now }
    }
}
