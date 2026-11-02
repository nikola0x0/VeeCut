import Foundation

/// What went wrong with an object tool, in Vee's words; cleared when the user dismisses it.
extension EditorViewModel {
    var canvasFailureMessage: String? {
        if let failure = subjectTrackingFailure { return Self.message(for: failure) }
        if let failure = subjectFollowFailure { return Self.message(for: failure) }
        if let failure = stickerFailure { return Self.message(for: failure) }
        return nil
    }

    func dismissCanvasFailure() {
        if subjectTrackingFailure != nil {
            subjectTrackingFailure = nil
        } else if subjectFollowFailure != nil {
            subjectFollowFailure = nil
        } else {
            stickerFailure = nil
        }
    }

    private static func message(for failure: StickerFailure) -> String {
        switch failure {
        case .noProject: L10n.string("Save the project first, so the sticker has somewhere to live.")
        case .emptyDescription: L10n.string("Describe the sticker in a few words.")
        case .missingAPIKey: L10n.string("Add a Meta Model API key in Settings to draw stickers.")
        case .contentPolicy: L10n.string("Muse Image won\u{2019}t draw that. Try describing it differently.")
        case .nothingToCutOut: L10n.string("Couldn\u{2019}t cut the sticker out of its background. Try again.")
        case .subject(let failure): Self.message(for: failure)
        case .failed: L10n.string("Couldn\u{2019}t reach Muse Image. Check your connection and try again.")
        }
    }

    private static func message(for failure: SubjectFollowFailure) -> String {
        switch failure {
        case .clipNotFound: L10n.string("That clip is no longer on the timeline.")
        case .notVisual: L10n.string("Audio clips can\u{2019}t follow an object.")
        case .sameClip: L10n.string("A clip can\u{2019}t follow an object inside itself.")
        case .maskNotLoaded: L10n.string("The object\u{2019}s tracking is still loading. Try again in a moment.")
        case .noOverlap: L10n.string("The text and the object\u{2019}s clip don\u{2019}t overlap on the timeline.")
        case .subjectAbsent: L10n.string("The object doesn\u{2019}t show while this clip plays.")
        }
    }

    private static func message(for failure: SubjectTrackingFailure) -> String {
        switch failure {
        case .missingAPIKey: L10n.string("Add a Meta Model API key in Settings to track subjects.")
        case .notFound: L10n.string("No subject found there. Try scribbling right on it.")
        case .modelFailed: L10n.string("SAM couldn't follow that spot. Scribble across more of the subject, or try another frame.")
        case .serviceFailed: L10n.string("Meta\u{2019}s SAM service had a problem. Try again in a moment.")
        case .failed: L10n.string("Tracking failed. Try again.")
        }
    }
}
