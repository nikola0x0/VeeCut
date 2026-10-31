import AppKit

/// Hold-to-talk in Active mode: record, transcribe with Muse Voice, then answer the tip or act on the request.
extension EditorViewModel {
    func startCoachListening() {
        guard coachMode == .active, !coachListening else { return }
        coachListening = true
        coachVoice.stop()
        let capture = voiceCapture
        coachListenTask = Task { [weak self] in
            do {
                try await capture.start()
            } catch {
                self?.coachListening = false
                self?.reportCoachVoiceFailure(error)
            }
        }
    }

    func finishCoachListening() {
        guard coachListening else { return }
        coachListening = false
        let capture = voiceCapture
        let starting = coachListenTask
        let locale = coachSpeechLocale
        coachListenTask = Task { [weak self] in
            await starting?.value
            let url: URL
            do { url = try await capture.stop() } catch { return }
            defer { Task.detached { try? FileManager.default.removeItem(at: url) } }
            do {
                let heard = try await MetaVoiceTranscription.transcribe(fileURL: url, locale: locale).text
                guard !Task.isCancelled else { return }
                self?.handleCoachUtterance(heard)
            } catch {
                self?.reportCoachVoiceFailure(error)
            }
        }
    }

    /// A yes or no answers the current tip; while the coach asks, the words are the brief; otherwise the agent acts on them.
    func handleCoachUtterance(_ text: String) {
        switch CoachReplyRouter.route(text) {
        case .accept:
            if let nudge = coachNudges.first { apply(nudge) }
        case .decline:
            if let nudge = coachNudges.first { dismiss(nudge) }
        case .request(let request):
            guard !request.isEmpty else { return }
            if case .asking = coach {
                submitBrief(request, style: nil)
            } else {
                coachAwaitingReply = true
                agentService.send(text: request, mentions: [])
            }
        }
    }

    /// Speaks the first sentence of the agent's answer to a spoken request.
    func coachReplyFinished(_ reply: String?) {
        guard coachAwaitingReply else { return }
        coachAwaitingReply = false
        guard coachMode == .active, let reply, !reply.isEmpty else { return }
        let sentence = reply.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? reply
        coachVoice.speak(sentence)
    }

    private var coachSpeechLocale: Locale {
        Locale(identifier: Locale.preferredLanguages.first ?? "en")
    }

    private func reportCoachVoiceFailure(_ error: Error) {
        let message = (error as? VoiceCapture.Failure) == .microphoneDenied
            ? L10n.string("VeeCut needs microphone access to hear you. Allow it in System Settings → Privacy & Security.")
            : L10n.string("Couldn't hear that. Try again.")
        mediaPanelToast = MediaPanelToast(message: message)
        Log.editor.error("coach voice failed error=\(String(describing: error))")
    }
}
