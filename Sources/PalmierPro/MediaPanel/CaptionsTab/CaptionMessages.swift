import Foundation

/// User-facing caption outcomes, shared by the Captions tab and Vee.
extension EditorViewModel {
    /// What to tell the user after generating captions; nil when captions were added for every source.
    func captionOutcomeMessage(_ generation: CaptionGeneration) -> String? {
        captionFailureNote(generation.failures) ?? (generation.createdIds.isEmpty ? L10n.string("No speech detected.") : nil)
    }

    func localizedCaptionError(_ error: Error) -> String {
        guard let error = error as? TranscriptionError else { return error.localizedDescription }
        return localizedTranscriptionError(error)
    }

    func localizedTranscriptionError(_ error: TranscriptionError) -> String {
        switch error {
        case .unsupportedLocale(let identifier):
            L10n.string("Transcription is not available for \(identifier).")
        case .modelInstallFailed(let reason):
            L10n.string("Could not install the on-device speech model: \(reason)")
        case .decodeFailed:
            L10n.string("Could not parse transcription result.")
        case .audioExtractionFailed(let reason):
            L10n.string("Audio extraction failed: \(reason)")
        case .analysisFailed(let reason):
            L10n.string("Transcription failed: \(reason)")
        }
    }

    /// Names the sources that got no captions, so a partial result isn't mistaken for silence.
    func captionFailureNote(_ failures: [EditorViewModel.CaptionSourceFailure]) -> String? {
        guard let first = failures.first else { return nil }
        let name = mediaAssets.first { $0.id == first.mediaRef }?.name ?? first.mediaRef
        let reason = switch first.cause {
        case .offline: L10n.string("The media is offline.")
        case .transcription(let error): localizedTranscriptionError(error)
        case .other(let description): description
        }
        return failures.count == 1
            ? L10n.string("No captions for \u{201C}\(name)\u{201D}. \(reason)")
            : L10n.string("No captions for \(failures.count) clips, including \u{201C}\(name)\u{201D}. \(reason)")
    }
}
