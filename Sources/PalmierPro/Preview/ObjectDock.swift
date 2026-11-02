import SwiftUI

/// The dock under the preview: pick tools, the current clip's objects, and the selected object's looks.
struct ObjectDock: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        DockContent(clipId: editor.shelfClipId)
            .padding(AppTheme.Spacing.mdLg)
    }
}

/// Split from the dock so playhead moves re-render only when the dock's clip changes.
private struct DockContent: View {
    @Environment(EditorViewModel.self) private var editor
    let clipId: String?
    @State private var namingObject = false
    /// The how-to card for the tool just switched on; it goes when the tool does or tracking starts.
    @State private var hint: ToolHint?

    private var looksSubject: CanvasSubject? {
        guard editor.objectCardOpen, let subject = editor.validCanvasSubject, subject.clipId == clipId else { return nil }
        return subject
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            VStack(spacing: AppTheme.Spacing.xs) {
                tools
                if let clipId {
                    Rectangle()
                        .fill(AppTheme.Border.subtleColor)
                        .frame(width: AppTheme.IconSize.md, height: AppTheme.BorderWidth.hairline)
                        .padding(.vertical, AppTheme.Spacing.xxs)
                    objects(clipId)
                }
            }
            .dockSurface()
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                if let trackingClipId = editor.subjectTrackingClipId {
                    TrackingIndicator(clipId: trackingClipId)
                        .dockSurface()
                        .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
                }
                if let hint, editor.canvasSelection == hint.kind, !editor.isSubjectTracking {
                    ToolCard(icon: hint.icon, title: hint.title, text: hint.text) { self.hint = nil }
                        .dockSurface()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                if namingObject, let clipId, !editor.isSubjectTracking {
                    ToolCard(icon: .search, title: L10n.string("Find"),
                             text: L10n.string("Describe what to track, like sky or the red car."),
                             onClose: { namingObject = false }) {
                        TrackByNameField(onTrack: { name in
                            editor.trackSubject(named: name, clipId: clipId)
                            namingObject = false
                        }, onCancel: { namingObject = false })
                    }
                    .dockSurface()
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                if let subject = looksSubject {
                    DockLooksRow(subject: subject)
                        .dockSurface()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: AppTheme.Anim.transition), value: looksSubject)
        .animation(.easeOut(duration: AppTheme.Anim.transition), value: hint)
        .animation(.easeOut(duration: AppTheme.Anim.transition), value: namingObject)
        .animation(AppTheme.Anim.fluid, value: editor.subjectTrackingClipId)
    }

    private var tools: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            canvasTool(.subject, title: L10n.string("Pick"), icon: .scribble,
                       help: L10n.string("Pick on video: scribble over, circle, or click what to track"),
                       hint: L10n.string("Scribble over the subject, circle it, or click it. \u{2325}-click picks the exact spot under the cursor."))
            canvasTool(.brush, title: L10n.string("Brush"), icon: .brush,
                       help: L10n.string("Brush: paint over a region and SAM snaps it to the edges"),
                       hint: L10n.string("Paint over the area. SAM snaps it to the edges and follows it."))
            toolButton(L10n.string("Find"), icon: .search, active: namingObject,
                       help: L10n.string("Find something in the clip by describing it, like sky or the red car")) {
                namingObject.toggle()
                if namingObject {
                    hint = nil
                    if let active = editor.canvasSelection { editor.toggleCanvasSelection(active) }
                }
            }
        }
        .disabled(clipId == nil || editor.isSubjectTracking)
        .help(clipId == nil ? L10n.string("Select a video clip") : "")
    }

    /// The whole frame, then each tracked object as its own round thumbnail.
    private func objects(_ clipId: String) -> some View {
        ViewThatFits(in: .vertical) {
            objectColumn(clipId)
            ScrollView(.vertical, showsIndicators: false) { objectColumn(clipId) }
        }
        .disabled(editor.isSubjectTracking)
    }

    private func objectColumn(_ clipId: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            wholeClipChip(clipId)
            ForEach(editor.canvasObjects(clipId: clipId)) { mask in
                ObjectChip(mask: mask, clipId: clipId)
            }
        }
    }

    private func canvasTool(_ kind: CanvasSelectionKind, title: String, icon: PhosphorIcon, help: String, hint text: String) -> some View {
        toolButton(title, icon: icon, active: editor.canvasSelection == kind, help: help) {
            editor.toggleCanvasSelection(kind)
            hint = editor.canvasSelection == kind ? ToolHint(kind: kind, icon: icon, title: title, text: text) : nil
            if hint != nil { namingObject = false }
        }
    }

    private func toolButton(_ title: String, icon: PhosphorIcon, active: Bool, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PhosphorImage(icon)
                .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
                .stripButton(fill: active ? AppTheme.Accent.canvasAI : AppTheme.Interaction.fill(AppTheme.Opacity.faint),
                             foreground: active ? AppTheme.MediaOverlay.primaryColor : AppTheme.Text.primaryColor)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
    }

    private func wholeClipChip(_ clipId: String) -> some View {
        let selected = editor.validCanvasSubject == CanvasSubject(clipId: clipId, maskId: nil)
        return Button {
            editor.toggleCanvasObject(clipId: clipId, maskId: nil)
        } label: {
            PhosphorImage(.selection)
                .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
                .stripButton(fill: selected ? AppTheme.Accent.canvasAI : AppTheme.Tint.blushColor,
                             foreground: selected ? AppTheme.MediaOverlay.primaryColor : AppTheme.Tint.inkColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("Full Frame"))
        .help(L10n.string("Presets and changes for the full frame, not one object"))
    }
}

private struct ObjectChip: View {
    @Environment(EditorViewModel.self) private var editor
    let mask: TrackedMask
    let clipId: String

    var body: some View {
        let subject = CanvasSubject(clipId: clipId, maskId: mask.id)
        let selected = editor.validCanvasSubject == subject
        let source = editor.thumbnailSource(maskId: mask.id, clipId: clipId)
        Button {
            editor.toggleCanvasObject(clipId: clipId, maskId: mask.id)
        } label: {
            ObjectThumbnail(maskId: mask.id)
                .stripButton(fill: selected ? AppTheme.Accent.canvasAI : AppTheme.ObjectKind.fill,
                             foreground: selected ? AppTheme.MediaOverlay.primaryColor : AppTheme.Tint.inkColor)
        }
        .buttonStyle(.plain)
        .help(mask.label)
        .accessibilityLabel(Text(verbatim: mask.label))
        .onHover { hovering in
            if hovering {
                editor.hoveredObject = subject
            } else if editor.hoveredObject == subject {
                editor.hoveredObject = nil
            }
        }
        .contextMenu {
            Button(L10n.string("Rename")) {
                editor.selectCanvasObject(clipId: clipId, maskId: mask.id)
                editor.renamingObjectId = mask.id
            }
            Button(L10n.string("Ask in Chat")) { editor.insertObjectMention(subject) }
            Button(L10n.string("Delete"), role: .destructive) { editor.deleteSubject(maskId: mask.id) }
        }
        .task(id: source) {
            guard let source else { return }
            await editor.objectThumbnails.load(
                maskId: mask.id, url: source.url, sourceSeconds: source.sourceSeconds, bounds: source.bounds
            )
        }
    }
}

/// The object's cached crop as a round avatar, or a placeholder while it renders.
struct ObjectThumbnail: View {
    @Environment(EditorViewModel.self) private var editor
    let maskId: String

    var body: some View {
        Group {
            if let image = editor.objectThumbnails.images[maskId] {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle().fill(AppTheme.MediaOverlay.backgroundColor.opacity(AppTheme.Opacity.faint))
            }
        }
        .frame(width: AppTheme.ComponentSize.objectThumbnail, height: AppTheme.ComponentSize.objectThumbnail)
        .clipShape(Circle())
    }
}

/// The selected object's looks, described looks, and links to chat and the inspector.
private struct DockLooksRow: View {
    @Environment(EditorViewModel.self) private var editor
    let subject: CanvasSubject

    var body: some View {
        // A narrow preview stacks the actions under the field, then drops their titles; it never runs under the inspector.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.xs) {
                looksAndField
                actions.labelStyle(.titleAndIcon)
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                looksAndField
                actions.labelStyle(.titleAndIcon)
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                looksAndField
                actions.labelStyle(.iconOnly)
            }
        }
    }

    private var looksAndField: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            looksMenu
            DescribeLookField(
                isBuilding: editor.isRequestingLook,
                status: editor.lookRequestStatus.flatMap { $0.clipId == subject.clipId ? $0 : nil },
                onCancel: { editor.cancelLookRequest() }
            ) { editor.requestLook(described: $0, clipId: subject.clipId, maskId: subject.maskId) }
        }
    }

    /// One-click presets in a menu: quick ones for the object or its background, then full ones for both.
    private var looksMenu: some View {
        Menu {
            Section(L10n.string("Quick")) {
                Button(L10n.string("Smooth Skin")) {
                    editor.smoothSkin(clipId: subject.clipId, person: subject.maskId)
                }
                .disabled(editor.isSubjectTracking)
                .help(L10n.string("Retouch the face: finds it with SAM the first time"))
                if let maskId = subject.maskId {
                    ForEach(SubjectLook.allCases.filter { $0.placement != .both }, id: \.self) { look in
                        Button(L10n.string(key: look.titleKey)) {
                            editor.applySubjectLook(look, clipId: subject.clipId, maskId: maskId)
                        }
                    }
                }
            }
            Section(L10n.string("Full")) {
                ForEach(SubjectLook.allCases.filter { $0.placement == .both }, id: \.self) { look in
                    Button(L10n.string(key: look.titleKey)) {
                        editor.applySubjectLook(look, clipId: subject.clipId, maskId: subject.maskId)
                    }
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "wand.and.stars")
                Text(L10n.string("Presets"))
                Image(systemName: "chevron.down")
                    .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.bold))
            }
            .dockPill(fill: AppTheme.Tint.lilacColor, foreground: AppTheme.Tint.inkColor)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.string("Apply a one-click preset"))
    }

    private var actions: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            StickerButton(subject: subject)
            if subject.maskId != nil {
                Button {
                    if case .failure(let failure) = editor.addFollowingLabel(for: subject) {
                        editor.subjectFollowFailure = failure
                    }
                } label: {
                    Label(L10n.string("Label"), systemImage: "character.textbox")
                            .dockPill(fill: AppTheme.Interaction.fill(AppTheme.Opacity.faint), foreground: AppTheme.Text.primaryColor)
                }
                .buttonStyle(.plain)
                .help(L10n.string("Add the object\u{2019}s name as text that follows it"))
            }
            Button {
                editor.insertObjectMention(subject)
            } label: {
                Label(L10n.string("Ask in Chat"), systemImage: "bubble.left.and.text.bubble.right")
                    .dockPill(fill: AppTheme.Background.clearColor, foreground: AppTheme.Accent.canvasAI)
                    .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.Accent.canvasAI, lineWidth: AppTheme.BorderWidth.thin))
            }
            .buttonStyle(.plain)
            .help(L10n.string("Tag this in the chat and describe what to do"))
            Button {
                editor.showCanvasObjectDetails()
            } label: {
                Label(L10n.string("Tune…"), systemImage: "slider.horizontal.3")
                    .dockPill(fill: AppTheme.Interaction.fill(AppTheme.Opacity.faint), foreground: AppTheme.Text.primaryColor)
            }
            .buttonStyle(.plain)
            .help(subject.maskId == nil
                ? L10n.string("Tune the full frame in the Adjust tab")
                : L10n.string("Tune each effect in the Subject tab"))
        }
        .fixedSize()
    }
}

/// SAM tracking progress at the dock's trailing end. Its own view so progress ticks redraw only the pill.
private struct TrackingIndicator: View {
    @Environment(EditorViewModel.self) private var editor
    let clipId: String

    var body: some View {
        let progress = min(max(editor.objectTrackingProgress[clipId] ?? 0, 0), 1)
        ProgressPill(
            progress: progress,
            label: L10n.string("Tracking \(Int((progress * 100).rounded()))%"),
            widestLabel: L10n.string("Tracking \(100)%"),
            cancelHelp: L10n.string("Cancel tracking")
        ) { _ = editor.cancelSubjectInteraction() }
    }
}

/// A pill that fills left to right with progress, with a cancel button. `widestLabel` reserves a constant width.
private struct ProgressPill: View {
    let progress: Double
    let label: String
    let widestLabel: String?
    let cancelHelp: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ZStack(alignment: .leading) {
                if let widestLabel { Text(verbatim: widestLabel).hidden() }
                Text(verbatim: label)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.bold))
                    .frame(width: AppTheme.IconSize.xxs, height: AppTheme.IconSize.xxs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(cancelHelp)
        }
        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
        .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
        .padding(.horizontal, AppTheme.Spacing.smMd)
        .frame(height: AppTheme.IconSize.lgXl)
        .background {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(AppTheme.Palette.periwinkleLight))
                    Rectangle()
                        .fill(Color(AppTheme.Palette.periwinkleDeep))
                        .frame(width: geometry.size.width * min(max(progress, 0), 1))
                }
            }
            .clipShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: AppTheme.Anim.transition), value: progress)
        }
        .fixedSize()
    }
}

/// Shows its content at full width when it fits, otherwise scrolls it horizontally.
/// Finds and tracks everything matching a short description ("sky", "the red car") instead of marking it.
struct TrackByNameField: View {
    let onTrack: (String) -> Void
    var onCancel: () -> Void = {}
    @State private var name = ""
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            TextField(L10n.string("Find: sky, the red car…"), text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: AppTheme.FontSize.md))
                .focused($focused)
                .onSubmit(track)
                .onExitCommand(perform: onCancel)
                .padding(.horizontal, AppTheme.Spacing.smMd)
                .padding(.vertical, AppTheme.Spacing.sm)
                .veeField(focused: focused)
                .accessibilityLabel(L10n.string("Find"))
            Button(L10n.string("Find"), action: track)
                .buttonStyle(.capsule(.prominent, size: .regular))
                .disabled(trimmed.isEmpty)
        }
        .padding(.top, AppTheme.Spacing.xs)
        .onAppear { focused = true }
    }

    private func track() {
        guard !trimmed.isEmpty else { return }
        onTrack(trimmed)
        name = ""
    }
}

/// Describes a look in words ("warm golden hour", "90s film") for Muse Spark to build.
struct DescribeLookField: View {
    /// While Muse Spark builds the look, the field itself fills left to right and offers cancel.
    let isBuilding: Bool
    /// The clip's last finished request, shown in the empty field.
    let status: LookRequestStatus?
    let onCancel: () -> Void
    let onCreate: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: isBuilding ? "sparkles" : statusSymbol)
                .foregroundStyle(isBuilding ? AppTheme.MediaOverlay.primaryColor : statusColor)
            if isBuilding {
                Text(L10n.string("Muse Spark is building the look…"))
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.bold))
                        .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
                        .frame(width: AppTheme.IconSize.xxs, height: AppTheme.IconSize.xxs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string("Cancel"))
            } else {
                TextField(String(), text: $text, prompt: Text(statusPrompt ?? L10n.string("Describe a change…")))
                    .textFieldStyle(.plain)
                    .onSubmit(create)
                    .accessibilityLabel(L10n.string("Describe a look"))
            }
        }
        .font(.system(size: AppTheme.FontSize.sm))
        .padding(.horizontal, AppTheme.Spacing.smMd)
        .frame(width: AppTheme.ComponentSize.dockDescribeWidth, height: AppTheme.IconSize.lgXl)
        .background {
            if isBuilding {
                BuildProgressFill()
            } else {
                Capsule(style: .continuous).fill(AppTheme.Interaction.fill(AppTheme.Opacity.faint))
            }
        }
        .help(statusDetail ?? L10n.string("Describe a look in words, like warm golden hour, and Muse Spark builds it"))
    }

    private var statusSymbol: String {
        switch status {
        case .applied: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .running, nil: "sparkles"
        }
    }

    private var statusColor: Color {
        switch status {
        case .applied: AppTheme.Status.successColor
        case .failed: AppTheme.Status.warningColor
        case .running, nil: AppTheme.Accent.canvasAI
        }
    }

    private var statusPrompt: String? {
        switch status {
        case .applied(_, let name, _, _): L10n.string("Applied \u{201C}\(name)\u{201D}. Describe another…")
        case .failed(_, .missingAPIKey): L10n.string("Add a Meta API key in Settings")
        case .failed(_, .unusable): L10n.string("Couldn\u{2019}t build that look")
        case .failed(_, .failed): L10n.string("Couldn\u{2019}t reach Muse Spark")
        case .running, nil: nil
        }
    }

    private var statusDetail: String? {
        switch status {
        case .applied(_, _, _, let skipped) where !skipped.isEmpty:
            L10n.string("Skipped unsupported: \(skipped.joined(separator: ", "))")
        case .failed(_, .missingAPIKey): L10n.string("Add a Meta Model API key in Settings to describe looks.")
        case .failed(_, .unusable): L10n.string("Muse Spark couldn\u{2019}t build that look. Try describing it differently.")
        case .failed(_, .failed): L10n.string("Couldn\u{2019}t reach Muse Spark. Check your connection and try again.")
        case .applied, .running, nil: nil
        }
    }

    private func create() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onCreate(text)
        text = ""
    }
}

/// Asks Muse Image for a sticker; on an object it rides on it, on the full frame it sits centered.
private struct StickerButton: View {
    @Environment(EditorViewModel.self) private var editor
    let subject: CanvasSubject
    @State private var asking = false
    @State private var text = ""

    var body: some View {
        if editor.isMakingSticker {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "face.smiling")
                Text(L10n.string("Muse Image is drawing…"))
                    .lineLimit(1)
                Button { editor.cancelSticker() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.bold))
                        .frame(width: AppTheme.IconSize.xxs, height: AppTheme.IconSize.xxs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string("Cancel"))
            }
            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
            .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
            .padding(.horizontal, AppTheme.Spacing.smMd)
            .frame(height: AppTheme.IconSize.lgXl)
            .background { BuildProgressFill() }
            .fixedSize()
        } else {
            Button { asking = true } label: {
                Label(L10n.string("Sticker"), systemImage: "face.smiling")
                    .dockPill(fill: AppTheme.Interaction.fill(AppTheme.Opacity.faint), foreground: AppTheme.Text.primaryColor)
            }
            .buttonStyle(.plain)
            .help(subject.maskId == nil
                ? L10n.string("Draw a sticker with Muse Image")
                : L10n.string("Draw a sticker with Muse Image that follows this object"))
            .popover(isPresented: $asking, arrowEdge: .top) { form }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(prompt)
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
            TextField(L10n.string("A cartoon golden crown"), text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            HStack {
                Spacer()
                Button(L10n.string("Create"), action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(width: AppTheme.ComponentSize.dockDescribeWidth)
    }

    private var prompt: String {
        guard let maskId = subject.maskId, let name = editor.trackedMask(id: maskId)?.label else {
            return L10n.string("Describe a sticker")
        }
        return L10n.string("Describe a sticker for \(name)")
    }

    private func create() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        editor.makeSticker(description: text, subject: subject.maskId == nil ? nil : subject)
        asking = false
        text = ""
    }
}

/// Muse Spark and Muse Image report no progress, so the fill eases toward 90% over their usual 8–10 s.
/// Created when a build starts, so its start date is that build's.
private struct BuildProgressFill: View {
    @State private var started = Date.now
    private static let timeConstant = 4.0
    private static let ceiling = 0.9

    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            let elapsed = max(context.date.timeIntervalSince(started), 0)
            let progress = Self.ceiling * (1 - exp(-elapsed / Self.timeConstant))
            Rectangle()
                .fill(Color(AppTheme.Palette.periwinkleDeep))
                .scaleEffect(x: progress, y: 1, anchor: .leading)
                .background(Color(AppTheme.Palette.periwinkleLight))
                .clipShape(Capsule(style: .continuous))
        }
    }
}

private extension View {
    /// The floating rounded bar the dock and its looks row sit on.
    func dockSurface() -> some View {
        padding(.horizontal, AppTheme.Spacing.smMd)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous).fill(AppTheme.Background.raisedColor))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .stroke(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
            )
            .shadow(AppTheme.Shadow.md)
    }

    /// A square button in the tool strip.
    func stripButton(fill: Color, foreground: Color) -> some View {
        font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
            .foregroundStyle(foreground)
            .frame(width: AppTheme.IconSize.xl, height: AppTheme.IconSize.xl)
            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(fill))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    func dockPill(fill: Color, foreground: Color, leadingInset: CGFloat = AppTheme.Spacing.smMd) -> some View {
        font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
            .foregroundStyle(foreground)
            .padding(.leading, leadingInset)
            .padding(.trailing, AppTheme.Spacing.smMd)
            .frame(height: AppTheme.IconSize.lgXl)
            .background(Capsule(style: .continuous).fill(fill))
            .contentShape(Capsule())
    }
}

private struct ToolHint: Equatable {
    let kind: CanvasSelectionKind
    let icon: PhosphorIcon
    let title: String
    let text: String
}

/// A tool's card beside the tool strip: how to use it, plus any controls it needs.
private struct ToolCard<Accessory: View>: View {
    let icon: PhosphorIcon
    let title: String
    let text: String
    let onClose: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
            PhosphorImage(icon)
                .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
                .foregroundStyle(AppTheme.Tint.inkColor)
                .frame(width: AppTheme.IconSize.lg, height: AppTheme.IconSize.lg)
                .background(Circle().fill(AppTheme.Tint.lilacColor))
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(verbatim: title)
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(verbatim: text)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
            .frame(maxWidth: AppTheme.Coach.toolHintWidth, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .frame(width: AppTheme.IconSize.xs, height: AppTheme.IconSize.xs)
            }
            .buttonStyle(.plain)
            .help(L10n.string("Close"))
        }
    }
}

extension ToolCard where Accessory == EmptyView {
    init(icon: PhosphorIcon, title: String, text: String, onClose: @escaping () -> Void) {
        self.init(icon: icon, title: title, text: text, onClose: onClose) { EmptyView() }
    }
}
