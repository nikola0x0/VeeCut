import SwiftUI

/// Looks applied inside or outside a clip's tracked subjects, each effect tunable in place.
struct SubjectTab: View {
    @Environment(EditorViewModel.self) private var editor
    let clip: Clip

    /// Subjects tracked on this clip's media, the one just selected on the canvas first.
    private var masks: [TrackedMask] {
        let all = editor.trackedMasks(forMedia: clip.mediaRef)
        guard let current = editor.canvasSubject, current.clipId == clip.id,
              let index = all.firstIndex(where: { $0.id == current.maskId }) else { return all }
        var ordered = all
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    var body: some View {
        addSubjectBar
        looksGroup(target: masks.first)
        if masks.isEmpty {
            emptyState
        } else {
            ForEach(masks) { mask in
                subjectGroup(mask)
            }
            backgroundGroup
        }
    }

    // MARK: - Background

    /// One background per clip: everything outside the subjects it keeps sharp.
    private var backgroundGroup: some View {
        let regions = (clip.effectRegions ?? []).filter(\.matte.invert)
        let kept = Set(regions.first?.matte.maskIds ?? masks.map(\.id))
        let anyMaskId = masks[0].id
        return EditorPanelGroup(L10n.string("Background")) {
            EmptyView()
        } content: {
            quickActions(outside: true, maskId: anyMaskId)
            addEffectMenu(outside: true, maskId: anyMaskId)
            if masks.count > 1 || !regions.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(L10n.string("Keep sharp"))
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                    ForEach(masks) { mask in
                        Toggle(isOn: Binding(
                            get: { kept.contains(mask.id) },
                            set: { editor.setKeepsSharp($0, maskId: mask.id, clipId: clip.id) }
                        )) {
                            Text(verbatim: mask.label).font(.system(size: AppTheme.FontSize.sm))
                        }
                        .toggleStyle(.checkbox)
                        .disabled(regions.isEmpty || (kept.contains(mask.id) && kept.count == 1))
                    }
                }
            }
            ForEach(regions) { region in
                regionSection(region)
            }
        }
    }

    private var addSubjectBar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Button {
                    if editor.canvasSelection != .subject { editor.toggleCanvasSelection(.subject) }
                } label: {
                    Label(L10n.string("Select Subject"), systemImage: "scribble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.capsule(.prominent, size: .regular))
                Button {
                    if editor.canvasSelection != .area { editor.toggleCanvasSelection(.area) }
                } label: {
                    Label(L10n.string("Draw Area"), systemImage: "square.dashed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.capsule(.secondary, size: .regular))
            }
            TrackByNameField { editor.trackSubject(named: $0, clipId: clip.id) }
        }
        .disabled(editor.isSubjectTracking)
        .padding(AppTheme.EditorPanel.contentInsets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Background.surfaceColor)
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.mdLg) {
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: AppTheme.FontSize.title1))
                .foregroundStyle(AppTheme.Accent.canvasAI)
            Text(L10n.string("No subjects yet"))
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
            Text(L10n.string("Scribble over, circle, or click someone in the preview, or track an area by name like \u{201C}sky\u{201D}. VeeCut follows it through the clip so you can change just it or everything else. Draw Area marks a fixed part of the frame instead."))
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.xl)
    }

    private func subjectGroup(_ mask: TrackedMask) -> some View {
        let maskId = mask.id
        let regions = (clip.effectRegions ?? []).filter { !$0.matte.invert && $0.matte.maskId == maskId }
        return EditorPanelGroup(mask.label) {
            Button {
                editor.deleteSubject(maskId: maskId)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
                    .hoverHighlight()
            }
            .buttonStyle(.plain)
            .help(mask.isDrawnArea ? L10n.string("Delete this area and its looks") : L10n.string("Delete this subject and its looks"))
        } content: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(L10n.string("Name"))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .frame(width: AppTheme.Slider.labelColumn, alignment: .leading)
                SubjectNameField(name: mask.label) { editor.renameSubject(maskId: maskId, to: $0) }
            }
            Text(mask.isDrawnArea ? L10n.string("Drawn area. Stays in place for the whole clip.") : L10n.string("Tracked with SAM 3.1"))
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            quickActions(outside: false, maskId: maskId)
            addEffectMenu(outside: false, maskId: maskId)
            ForEach(regions) { region in
                regionSection(region)
            }
        }
    }

    // MARK: - Looks

    /// Full looks, as presets or described to Muse Spark: around one subject and the shared background,
    /// or for the whole clip when it has no subject.
    private func looksGroup(target mask: TrackedMask?) -> some View {
        EditorPanelGroup(L10n.string("Looks")) {
            EmptyView()
        } content: {
            Text(lookTargetDescription(mask))
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            HStack(spacing: AppTheme.Spacing.xs) {
                ForEach(SubjectLook.allCases.filter { $0.placement == .both }, id: \.self) { look in
                    Button {
                        editor.applySubjectLook(look, clipId: clip.id, maskId: mask?.id)
                    } label: {
                        Text(L10n.string(key: look.titleKey))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                }
            }
            DescribeLookField { editor.requestLook(described: $0, clipId: clip.id, maskId: mask?.id) }
                .disabled(editor.isRequestingLook)
            if let status = editor.lookRequestStatus, status.clipId == clip.id {
                lookRequestStatusRow(status)
            }
        }
    }

    private func lookTargetDescription(_ mask: TrackedMask?) -> String {
        guard let mask else { return L10n.string("Applies to the whole clip. Tune it in the Adjust tab.") }
        return masks.count > 1
            ? L10n.string("Applies to \(mask.label) and the background.")
            : L10n.string("Applies to the subject and the background.")
    }

    @ViewBuilder
    private func lookRequestStatusRow(_ status: LookRequestStatus) -> some View {
        switch status {
        case .running:
            HStack(spacing: AppTheme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(L10n.string("Muse Spark is building the look…"))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                Spacer(minLength: 0)
                Button(L10n.string("Cancel")) { editor.cancelLookRequest() }
                    .controlSize(.small)
            }
        case .applied(_, let name, let wholeClip, let skipped):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(wholeClip
                    ? L10n.string("Applied \u{201C}\(name)\u{201D}. Tune it in the Adjust tab.")
                    : L10n.string("Applied \u{201C}\(name)\u{201D}. Tune it below."))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                if !skipped.isEmpty {
                    Text(L10n.string("Skipped unsupported: \(skipped.joined(separator: ", "))"))
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        case .failed(_, let failure):
            Text(lookFailureMessage(failure))
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lookFailureMessage(_ failure: LookRequestFailure) -> String {
        switch failure {
        case .missingAPIKey: L10n.string("Add a Meta Model API key in Settings to describe looks.")
        case .unusable: L10n.string("Muse Spark couldn\u{2019}t build that look. Try describing it differently.")
        case .failed: L10n.string("Couldn\u{2019}t reach Muse Spark. Check your connection and try again.")
        }
    }

    // MARK: - Quick actions

    private func quickActions(outside: Bool, maskId: String) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.xs), GridItem(.flexible(), spacing: AppTheme.Spacing.xs)],
            spacing: AppTheme.Spacing.xs
        ) {
            ForEach(SubjectLook.allCases.filter { $0.placement == (outside ? .background : .subject) }, id: \.self) { look in
                Button {
                    editor.applySubjectLook(look, clipId: clip.id, maskId: maskId)
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        sideSwatch(outside: outside)
                        Text(L10n.string(key: look.titleKey))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.capsule(.secondary, size: .regular))
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
            HStack(spacing: AppTheme.Spacing.sm) {
                sideSwatch(outside: outside)
                Text(outside ? L10n.string("Add to Background") : L10n.string("Add to Subject"))
            }
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
    }

    // MARK: - Applied regions

    private func regionSection(_ region: EffectRegion) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            sliderRow(
                label: L10n.string("Edge Feather"),
                value: region.matte.feather,
                range: EffectMatte.featherRange,
                defaultValue: EditorViewModel.subjectFeather,
                unit: "px"
            ) { value, commit in
                editor.editSubjectRegion(clipId: clip.id, regionId: region.id, commit: commit,
                                         actionName: L10n.string("Change Edge Feather")) { $0.matte.feather = value }
            }
            ForEach(region.effects) { effect in
                effectRows(effect, in: region)
            }
        }
    }

    @ViewBuilder
    private func effectRows(_ effect: Effect, in region: EffectRegion) -> some View {
        if let descriptor = EffectRegistry.descriptor(id: effect.type) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(L10n.string(key: descriptor.displayName))
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(effect.enabled ? AppTheme.Text.primaryColor : AppTheme.Text.mutedColor)
                Spacer(minLength: 0)
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
                Button {
                    editor.editSubjectRegion(clipId: clip.id, regionId: region.id, commit: true,
                                             actionName: L10n.string("Remove Effect")) { region in
                        region.effects.removeAll { $0.id == effect.id }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
                        .hoverHighlight(cornerRadius: AppTheme.Radius.xs)
                }
                .buttonStyle(.plain)
                .help(L10n.string("Remove"))
            }
            .padding(.top, AppTheme.Spacing.xs)
            ForEach(descriptor.params, id: \.key) { spec in
                sliderRow(
                    label: L10n.string(key: spec.label),
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
                .opacity(effect.enabled ? AppTheme.Opacity.opaque : AppTheme.Opacity.strong)
            }
        }
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

    // MARK: - Pieces

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

    private func sideSwatch(outside: Bool) -> some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous)
            .fill(Color(outside ? AppTheme.Palette.peach : AppTheme.Palette.lilac))
            .frame(width: AppTheme.ComponentSize.subjectSideSwatch, height: AppTheme.ComponentSize.subjectSideSwatch)
            .accessibilityHidden(true)
    }
}

/// Editable subject name; commits on Return or when focus leaves.
private struct SubjectNameField: View {
    let name: String
    let onCommit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(String(), text: $draft)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: AppTheme.FontSize.sm))
            .controlSize(.small)
            .focused($focused)
            .onSubmit { onCommit(draft) }
            .onChange(of: focused) { _, isFocused in if !isFocused { onCommit(draft) } }
            .onChange(of: name, initial: true) { _, newName in draft = newName }
            .onExitCommand { draft = name; focused = false }
            .accessibilityLabel(L10n.string("Subject name"))
    }
}

/// Tracks an area or object by name ("sky", "the red car") instead of drawing on it.
private struct TrackByNameField: View {
    let onTrack: (String) -> Void
    @State private var name = ""

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            TextField(L10n.string("Track by name: sky, the red car…"), text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: AppTheme.FontSize.sm))
                .controlSize(.small)
                .onSubmit(track)
                .accessibilityLabel(L10n.string("Track by name"))
            Button(L10n.string("Track"), action: track)
                .controlSize(.small)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func track() {
        onTrack(name)
        name = ""
    }
}

/// Describes a look in words ("warm golden hour", "90s film") for Muse Spark to build.
private struct DescribeLookField: View {
    let onCreate: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            TextField(L10n.string("Describe a look: warm golden hour, 90s film\u{2026}"), text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: AppTheme.FontSize.sm))
                .controlSize(.small)
                .onSubmit(create)
                .accessibilityLabel(L10n.string("Describe a look"))
            Button(L10n.string("Create"), action: create)
                .controlSize(.small)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func create() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onCreate(text)
        text = ""
    }
}
