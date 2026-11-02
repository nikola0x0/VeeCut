import AppKit
import Observation

// MARK: - Model

struct TourStep: Equatable {
    enum Kind: Equatable {
        case intro
        case spotlight(TourTarget)
        case outro
    }
    enum Prepare: Equatable {
        case none
        case selectClip
        case revealInspectorOverview
    }
    let kind: Kind
    let pose: VeeIllustration.Name
    let title: String
    let instruction: String
    var prepare: Prepare = .none
}

enum TourTarget: Equatable {
    case panel(EditorViewModel.FocusedPanel)
    case element(TourAnchorID)

    /// The panel that must be visible for this target to have a frame; nil for title-bar controls.
    var hostPanel: EditorViewModel.FocusedPanel? {
        switch self {
        case .panel(let p): return p
        case .element(let id): return id.hostPanel
        }
    }
}

/// Pinpointable controls. Add a case + its `hostPanel`, then tag the view with `.tourAnchor(_:)`.
enum TourAnchorID: Hashable {
    case veeButton
    case editorModeSwitch

    var hostPanel: EditorViewModel.FocusedPanel? {
        switch self {
        case .veeButton, .editorModeSwitch: nil
        }
    }
}

/// Weak box so registered anchor views aren't retained by the controller.
final class WeakView {
    weak var value: NSView?
    init(_ value: NSView?) { self.value = value }
}

// MARK: - Controller

@MainActor
@Observable
final class TourController {
    private(set) var stepIndex: Int?
    /// Highlighted region's frame in editor-view coords; set by the split controller.
    var targetFrame: CGRect?
    /// Live backing views for `.element` targets, registered by `.tourAnchor(_:)`.
    @ObservationIgnored var anchorViews: [TourAnchorID: WeakView] = [:]
    /// Bumped when an anchor view lays out, so the split controller recomputes the
    /// frame for controls that appear/animate inside a panel.
    private(set) var anchorRevision = 0
    func anchorDidLayout() { anchorRevision &+= 1 }
    @ObservationIgnored private weak var editor: EditorViewModel?

    private(set) var steps: [TourStep] = []

    var count: Int { steps.count }

    var spotlightCount: Int {
        steps.reduce(0) { if case .spotlight = $1.kind { return $0 + 1 }; return $0 }
    }

    var currentStep: TourStep? {
        guard let i = stepIndex, steps.indices.contains(i) else { return nil }
        return steps[i]
    }

    private static let seenKey = "tourSeen"

    /// Runs the tour the first time any project opens on this Mac.
    func startIfFirstRun(in editor: EditorViewModel, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Self.seenKey) else { return }
        defaults.set(true, forKey: Self.seenKey)
        start(in: editor)
    }

    func start(in editor: EditorViewModel) {
        self.editor = editor
        steps = Self.makeSteps(editor: editor)
        applyStep(0)
    }

    func advance() {
        guard let i = stepIndex else { return }
        if steps.indices.contains(i + 1) { applyStep(i + 1) } else { end() }
    }

    func back() {
        guard let i = stepIndex, i > 0 else { return }
        applyStep(i - 1)
    }

    func end() {
        stepIndex = nil
        targetFrame = nil
        editor?.inspectorClipTabRequest = nil
    }

    /// Ensure a spotlight step's host panel is visible
    private func applyStep(_ index: Int) {
        guard let editor, steps.indices.contains(index) else { return }
        editor.maximizedPanel = nil
        let step = steps[index]
        if case .spotlight(let target) = step.kind {
            switch target.hostPanel {
            case .media: editor.mediaPanelVisible = true
            case .agent: editor.agentPanelVisible = true
            case .inspector: editor.inspectorPanelVisible = true
            case .timeline, .preview, nil: break
            }
        }
        applyPrepare(step.prepare, to: editor)
        stepIndex = index
    }

    private func applyPrepare(_ prepare: TourStep.Prepare, to editor: EditorViewModel) {
        switch prepare {
        case .none:
            editor.inspectorClipTabRequest = nil
        case .selectClip:
            editor.inspectorPanelVisible = true
            selectTourClip(in: editor)
            editor.inspectorClipTabRequest = nil
        case .revealInspectorOverview:
            editor.inspectorPanelVisible = true
            selectTourClip(in: editor)
            editor.inspectorClipTabRequest = .video
        }
    }

    private func selectTourClip(in editor: EditorViewModel) {
        guard let clipId = Self.firstVisualClipId(in: editor) else { return }
        // Replace selection so a prior multi-select cannot hide the clip inspector.
        editor.selectedGap = nil
        editor.selectedTimelineRange = nil
        editor.selectedClipIds = editor.expandToLinkGroup([clipId])
    }

    // MARK: - Step list

    private static func makeSteps(editor: EditorViewModel) -> [TourStep] {
        let hasVisualClip = firstVisualClipId(in: editor) != nil
        return [
            TourStep(kind: .intro, pose: .tourWelcome, title: L10n.string("Hi, I'm Vee!"),
                     instruction: L10n.string("I'm your editing buddy. Let me show you around. It only takes a minute.")),
            TourStep(kind: .spotlight(.element(.veeButton)), pose: .tourPointUp, title: L10n.string("Here's where I live"),
                     instruction: L10n.string("Click me, or press ⌥⌘A, whenever you want to chat. I can cut your clips, track people and things, and add stickers and captions.")),
            TourStep(kind: .spotlight(.panel(.agent)), pose: .tourChat, title: L10n.string("Just tell me what you want"),
                     instruction: L10n.string("Say it in plain words, like \"make a 30 second trailer\". Type @ to point me at a clip or an object.")),
            TourStep(kind: .spotlight(.element(.editorModeSwitch)), pose: .tourSwitch, title: L10n.string("Simple or Pro"),
                     instruction: L10n.string("Simple keeps the tools most edits need. Switch to Pro when you want every knob.")),
            TourStep(kind: .spotlight(.panel(.media)), pose: .tourFootage, title: L10n.string("Your footage goes here"),
                     instruction: L10n.string("Import clips or drop them in. I'll watch them and suggest what to make.")),
            TourStep(kind: .spotlight(.panel(.preview)), pose: .tourCamera, title: L10n.string("Watch and pick"),
                     instruction: L10n.string("Play your edit here. Click a person or thing in the frame and I'll follow it through the shot.")),
            TourStep(
                kind: .spotlight(.panel(.timeline)), pose: .tourTimeline, title: L10n.string("Your timeline"),
                instruction: hasVisualClip
                    ? L10n.string("Video on top, sound below. When we make a plan, the colored bar shows each part and how full it is. I picked a clip for you.")
                    : L10n.string("Video on top, sound below. When we make a plan, the colored bar shows each part and how full it is."),
                prepare: hasVisualClip ? .selectClip : .none
            ),
            TourStep(
                kind: .spotlight(.panel(.inspector)), pose: .tourTune, title: L10n.string("Fine-tune it"),
                instruction: L10n.string("Pick a clip to change its look, speed, sound and more."),
                prepare: hasVisualClip ? .revealInspectorOverview : .none
            ),
            TourStep(kind: .outro, pose: .tourDone, title: L10n.string("You're all set!"),
                     instruction: L10n.string("Bring in some footage and say hi. I'll take it from there.")),
        ]
    }

    private static func firstVisualClipId(in editor: EditorViewModel) -> String? {
        for track in editor.timeline.tracks {
            for clip in track.clips where clip.mediaType.isVisual && clip.mediaType != .text {
                if editor.mediaAssetsById[clip.mediaRef] != nil {
                    return clip.id
                }
            }
        }
        return nil
    }
}
