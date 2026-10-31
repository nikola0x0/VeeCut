import SwiftUI

/// One section's title, length, hint and suggested moments; Add places a moment, or drag it onto the timeline.
struct PlanSectionPopover: View {
    @Environment(EditorViewModel.self) private var editor
    let sectionId: String
    @State private var title = ""
    @State private var seconds = 0.0

    private var section: PlanSection? { editor.timeline.plan?.sections.first { $0.id == sectionId } }

    var body: some View {
        if let section {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    TextField(L10n.string("Section"), text: $title)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { editor.renamePlanSection(sectionId, to: title) }
                    TextField(L10n.string("Length"), value: $seconds, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: AppTheme.Coach.lengthFieldWidth)
                        .onSubmit { editor.setPlanSectionTarget(sectionId, seconds: seconds) }
                    Text(L10n.string("s"))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                }
                if !section.hint.isEmpty {
                    Text(verbatim: section.hint)
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                }
                Divider()
                if section.suggestions.isEmpty {
                    Text(L10n.string("No suggestions. Drag clips from Media onto this section."))
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            ForEach(section.suggestions, id: \.self) { moment in
                                suggestionRow(moment)
                            }
                        }
                    }
                    .frame(maxHeight: AppTheme.Coach.maxSuggestionsHeight)
                }
            }
            .padding(AppTheme.Spacing.lg)
            .frame(width: AppTheme.Coach.popoverWidth)
            .onAppear {
                title = section.title
                seconds = section.targetSeconds
            }
        }
    }

    private func suggestionRow(_ moment: PlanMoment) -> some View {
        let asset = editor.mediaAssets.first { $0.id == moment.assetId }
        return HStack(spacing: AppTheme.Spacing.sm) {
            MomentThumbnail(url: asset?.url, time: moment.start)
                .frame(width: AppTheme.Coach.thumbnailSize.width, height: AppTheme.Coach.thumbnailSize.height)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs))
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(verbatim: moment.note.isEmpty ? asset?.name ?? "" : moment.note)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .lineLimit(1)
                Text(verbatim: "\(asset?.name ?? "") · \(String(format: "%.1f", moment.end - moment.start)) s")
                    .font(.system(size: AppTheme.FontSize.xxs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(L10n.string("Add")) { editor.placeMomentsReportingFailure([moment], in: sectionId) }
                .controlSize(.small)
                .disabled(asset == nil)
        }
        .contentShape(Rectangle())
        .draggable(MediaTab.assetDragString(forAssetId: moment.assetId, segment: moment.start...moment.end)) {
            MomentThumbnail(url: asset?.url, time: moment.start)
                .frame(width: AppTheme.Coach.thumbnailSize.width, height: AppTheme.Coach.thumbnailSize.height)
        }
    }
}
