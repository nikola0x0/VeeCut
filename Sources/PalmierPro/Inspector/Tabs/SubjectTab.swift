import SwiftUI

/// Fine-tuning for a clip's objects: a lilac or peach card per object, the shared background card, and edge softness.
struct SubjectTab: View {
    @Environment(EditorViewModel.self) private var editor
    let clip: Clip

    private var masks: [TrackedMask] { editor.trackedMasks(forMedia: clip.mediaRef) }

    /// The object selected in the dock, else every object on this clip's media.
    private var shownMasks: [TrackedMask] {
        guard let current = editor.validCanvasSubject, current.clipId == clip.id,
              let mask = masks.first(where: { $0.id == current.maskId }) else { return masks }
        return [mask]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.mdLg) {
            if masks.isEmpty {
                emptyState
            } else {
                ForEach(shownMasks) { mask in
                    objectCard(mask)
                }
                backgroundCard
                edgeSoftnessRow
            }
        }
        .padding(.horizontal, AppTheme.Spacing.smMd)
        .padding(.vertical, AppTheme.Spacing.smMd)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.mdLg) {
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: AppTheme.FontSize.title1))
                .foregroundStyle(AppTheme.Accent.canvasAI)
            Text(L10n.string("No subjects yet"))
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
            Text(L10n.string("Pick someone on the video, paint over a region, or find something by name from the dock under the preview. Fine-tune its effects here."))
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.xl)
    }

    // MARK: - Cards

    private func objectCard(_ mask: TrackedMask) -> some View {
        let regions = (clip.effectRegions ?? []).filter { !$0.matte.invert && $0.matte.maskId == mask.id }
        return SubjectCard(fill: AppTheme.ObjectKind.fill) {
            ObjectCardHeader(mask: mask, clipId: clip.id)
        } content: {
            effectRows(regions)
            addEffectMenu(outside: false, maskId: mask.id)
        }
    }

    private var backgroundCard: some View {
        let regions = (clip.effectRegions ?? []).filter(\.matte.invert)
        let kept = Set(regions.first?.matte.maskIds ?? masks.map(\.id))
        return SubjectCard(fill: AppTheme.Tint.peachColor) {
            Text(L10n.string("Background"))
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Tint.inkColor)
        } content: {
            effectRows(regions)
            addEffectMenu(outside: true, maskId: masks[0].id)
            if !regions.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(L10n.string("Keep sharp"))
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                    FlowChips {
                        ForEach(masks) { mask in
                            keepSharpChip(mask, kept: kept)
                        }
                    }
                }
            }
        }
    }

    private func keepSharpChip(_ mask: TrackedMask, kept: Set<String>) -> some View {
        let isKept = kept.contains(mask.id)
        return Button {
            editor.setKeepsSharp(!isKept, maskId: mask.id, clipId: clip.id)
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                ObjectThumbnail(maskId: mask.id)
                Text(verbatim: mask.label).lineLimit(1)
                if isKept { Image(systemName: "checkmark").font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.bold)) }
            }
            .font(.system(size: AppTheme.FontSize.sm))
            .foregroundStyle(AppTheme.Tint.inkColor)
            .padding(.leading, AppTheme.Spacing.xs)
            .padding(.trailing, AppTheme.Spacing.smMd)
            .frame(height: AppTheme.IconSize.lgXl)
            .background(Capsule(style: .continuous).fill(
                isKept ? AppTheme.ObjectKind.fill : AppTheme.Interaction.fill(AppTheme.Opacity.faint)
            ))
        }
        .buttonStyle(.plain)
        .disabled(isKept && kept.count == 1)
        .help(isKept ? L10n.string("Kept sharp: background effects skip it") : L10n.string("Background effects apply to it too"))
    }

    @ViewBuilder
    private var edgeSoftnessRow: some View {
        let preferred = editor.validCanvasSubject?.clipId == clip.id ? editor.validCanvasSubject?.maskId : nil
        if let softness = editor.edgeSoftness(clipId: clip.id, preferring: preferred) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                sliderRow(
                    label: L10n.string("Edge softness"),
                    value: softness.value,
                    range: EffectMatte.featherRange,
                    defaultValue: EditorViewModel.subjectFeather,
                    unit: "px"
                ) { value, commit in
                    editor.setEdgeSoftness(value, clipId: clip.id, commit: commit)
                }
                if softness.mixed {
                    Text(L10n.string("Mixed: dragging sets every region to the same softness."))
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            }
        }
    }

    // MARK: - Effect rows

    @ViewBuilder
    private func effectRows(_ regions: [EffectRegion]) -> some View {
        ForEach(regions) { region in
            ForEach(region.effects) { effect in
                if let descriptor = EffectRegistry.descriptor(id: effect.type) {
                    effectRow(effect, descriptor: descriptor, in: region)
                }
            }
        }
    }

    private func effectRow(_ effect: Effect, descriptor: EffectDescriptor, in region: EffectRegion) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.sm) {
                if let main = descriptor.params.first {
                    paramRow(effect, spec: main, label: L10n.string(key: descriptor.displayName), in: region)
                } else {
                    Text(L10n.string(key: descriptor.displayName))
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                    Spacer(minLength: 0)
                }
                Toggle(String(), isOn: Binding(
                    get: { effect.enabled },
                    set: { enabled in
                        editRegionEffect(effect.id, in: region, actionName: enabled
                            ? L10n.string("Enable Effect") : L10n.string("Disable Effect")) { $0.enabled = enabled }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(AppTheme.Accent.primary)
                .accessibilityLabel(L10n.string(key: descriptor.displayName))
            }
            let extra = descriptor.params.dropFirst()
            if extra.count == 1, let spec = extra.first {
                paramRow(effect, spec: spec, label: L10n.string(key: spec.label), in: region)
            } else if !extra.isEmpty {
                MoreSettings {
                    ForEach(extra, id: \.key) { spec in
                        paramRow(effect, spec: spec, label: L10n.string(key: spec.label), in: region)
                    }
                }
            }
        }
        .opacity(effect.enabled ? AppTheme.Opacity.opaque : AppTheme.Opacity.strong)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.string("Remove"), role: .destructive) {
                editor.editSubjectRegion(clipId: clip.id, regionId: region.id, commit: true,
                                         actionName: L10n.string("Remove Effect")) { region in
                    region.effects.removeAll { $0.id == effect.id }
                }
            }
        }
    }

    private func paramRow(_ effect: Effect, spec: EffectParamSpec, label: String, in region: EffectRegion) -> some View {
        sliderRow(
            label: label,
            value: effect.params[spec.key]?.resolved(at: 0, default: spec.defaultValue) ?? spec.defaultValue,
            range: spec.range,
            defaultValue: spec.defaultValue,
            unit: spec.unit
        ) { value, commit in
            editRegionEffect(effect.id, in: region, commit: commit,
                             actionName: L10n.string("Change \(L10n.string(key: spec.label))")) {
                $0.params[spec.key] = EffectParam(value: value)
            }
        }
    }

    private func addEffectMenu(outside: Bool, maskId: String) -> some View {
        let applied = Set((clip.effectRegions ?? [])
            .filter { $0.matte.invert == outside && (outside || $0.matte.maskId == maskId) }
            .flatMap { $0.effects.map(\.type) })
        let categories = Dictionary(grouping: EditorViewModel.subjectEffectDescriptors, by: \.category)
        return Menu {
            ForEach(categories.keys.sorted(), id: \.self) { category in
                Section(L10n.string(key: category)) {
                    ForEach(categories[category] ?? []) { descriptor in
                        Button(L10n.string(key: descriptor.displayName)) {
                            editor.addSubjectEffect(descriptor.id, outside: outside, clipId: clip.id, maskId: maskId)
                        }
                        .disabled(applied.contains(descriptor.id))
                    }
                }
            }
        } label: {
            Label(L10n.string("Add effect"), systemImage: "plus")
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Accent.canvasAI)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func editRegionEffect(
        _ effectId: String,
        in region: EffectRegion,
        commit: Bool = true,
        actionName: String,
        _ body: @escaping (inout Effect) -> Void
    ) {
        editor.editSubjectRegion(clipId: clip.id, regionId: region.id, commit: commit, actionName: actionName) { region in
            guard let index = region.effects.firstIndex(where: { $0.id == effectId }) else { return }
            body(&region.effects[index])
        }
    }

    private func sliderRow(
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        defaultValue: Double,
        unit: String,
        onEdit: @escaping (Double, Bool) -> Void
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(verbatim: label)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .lineLimit(1)
                .frame(width: AppTheme.Slider.labelColumn, alignment: .leading)
            AdjustSlider(
                value: value,
                range: range,
                defaultValue: defaultValue,
                onChanged: { onEdit($0, false) },
                onCommit: { onEdit($0, true) }
            )
            ScrubbableNumberField(
                value: value,
                range: range,
                format: EffectParamDisplay.format(for: range),
                valueSuffix: unit.isEmpty ? "" : " \(unit)",
                dragSensitivity: EffectParamDisplay.dragSensitivity(for: range),
                fieldWidth: AppTheme.EditorPanel.numericFieldWidth,
                onChanged: { onEdit($0, false) }
            ) { onEdit($0, true) }
        }
        .frame(height: AppTheme.EditorPanel.fieldMinHeight)
    }
}

/// An effect's further settings behind a "More" row that opens on a click anywhere on it.
private struct MoreSettings<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Button {
                withAnimation(.easeOut(duration: AppTheme.Anim.transition)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(L10n.string("More"))
                        .font(.system(size: AppTheme.FontSize.xs))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded { content }
        }
    }
}

/// A rounded card with a tinted header band; the chevron folds its body away.
private struct SubjectCard<Header: View, Content: View>: View {
    let fill: Color
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    @State private var isCollapsed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Button {
                    withAnimation(.easeOut(duration: AppTheme.Anim.transition)) { isCollapsed.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .foregroundStyle(AppTheme.Tint.inkColor)
                        .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? L10n.string("Expand") : L10n.string("Collapse"))
                header
            }
            .padding(.horizontal, AppTheme.Spacing.smMd)
            .frame(maxWidth: .infinity, minHeight: AppTheme.IconSize.xl, alignment: .leading)
            .background(fill)
            if !isCollapsed {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) { content }
                    .padding(AppTheme.Spacing.smMd)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(shape.fill(AppTheme.Background.raisedColor))
        .clipShape(shape)
        .overlay(shape.stroke(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline))
    }
}

/// Thumbnail, name with a pencil for inline rename, and a menu for chat and delete.
private struct ObjectCardHeader: View {
    @Environment(EditorViewModel.self) private var editor
    let mask: TrackedMask
    let clipId: String
    @State private var renaming = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ObjectThumbnail(maskId: mask.id)
            if renaming {
                TextField(String(), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit(commit)
                    .onExitCommand { renaming = false }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                    .accessibilityLabel(L10n.string("Object name"))
            } else {
                Text(verbatim: mask.label)
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .lineLimit(1)
                    .onTapGesture(count: 2, perform: startRename)
                Button(action: startRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                        .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
                        .hoverHighlight(cornerRadius: AppTheme.Radius.xs)
                }
                .buttonStyle(.plain)
                .help(L10n.string("Rename"))
            }
            Spacer(minLength: 0)
            Menu {
                Button(L10n.string("Ask in Chat")) { editor.insertObjectMention(CanvasSubject(clipId: clipId, maskId: mask.id)) }
                Button(L10n.string("Delete"), role: .destructive) { editor.deleteSubject(maskId: mask.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: AppTheme.FontSize.sm))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .foregroundStyle(AppTheme.Tint.inkColor)
        .help(L10n.string("Tracked with SAM 3.1"))
    }

    private func startRename() {
        draft = mask.label
        renaming = true
    }

    private func commit() {
        guard renaming else { return }
        renaming = false
        editor.renameSubject(maskId: mask.id, to: draft)
    }
}

/// Chips that wrap onto new lines when the inspector is narrow.
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlowLayout(spacing: AppTheme.Spacing.xs) { content }
    }
}

private struct FlowLayout: SwiftUI.Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, y: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, y: CGFloat, height: CGFloat)] = []
        var current: [Int] = [], rowWidth: CGFloat = 0, rowHeight: CGFloat = 0, y: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.isEmpty, rowWidth + spacing + size.width > width {
                rows.append((current, rowWidth, y, rowHeight))
                y += rowHeight + spacing
                current = []; rowWidth = 0; rowHeight = 0
            }
            rowWidth += (current.isEmpty ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
            current.append(index)
        }
        if !current.isEmpty { rows.append((current, rowWidth, y, rowHeight)) }
        return rows
    }
}
