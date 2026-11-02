import SwiftUI

/// Simple mode's inspector for one video clip: a look, speed, volume and smooth skin, built from the Pro rows.
extension InspectorView {
    @ViewBuilder
    func simpleClipInspector(clip: Clip, audioClips: [Clip]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
                lookSection(clipId: clip.id)
                speedSection(clips: ([clip] + audioClips).filter(\.supportsRetiming))
                if !audioClips.isEmpty {
                    EditorPanelGroup(L10n.string("Sound"), contentSpacing: AppTheme.Spacing.smMd) {
                        volumeRow(audios: audioClips)
                    }
                }
                EditorPanelGroup(L10n.string("Retouch"), contentSpacing: AppTheme.Spacing.smMd) {
                    Button(L10n.string("Smooth Skin")) { editor.smoothSkin(clipId: clip.id, person: nil) }
                        .disabled(editor.isSubjectTracking)
                        .help(L10n.string("Retouch the face: finds it with SAM the first time"))
                }
                Button(L10n.string("More Settings in Pro")) { editor.setEditorMode(.pro) }
                    .buttonStyle(.borderless)
                    .padding(AppTheme.Spacing.lg)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func lookSection(clipId: String) -> some View {
        EditorPanelGroup(L10n.string("Look"), contentSpacing: AppTheme.Spacing.smMd) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm), count: 3), spacing: AppTheme.Spacing.sm) {
                ForEach(SubjectLook.allCases.filter { $0.placement == .both }, id: \.self) { look in
                    Button {
                        editor.applySubjectLook(look, clipId: clipId, maskId: nil)
                    } label: {
                        Text(L10n.string(key: look.titleKey))
                            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                            .foregroundStyle(AppTheme.Text.primaryColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.EditorPanel.lookTileHeight)
                            .background(AppTheme.Background.raisedColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin))
                            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
