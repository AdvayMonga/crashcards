import Foundation
import AVFoundation
import Speech
import Observation

/// Drives a hands-free voice study loop over a `StudySession`:
/// speak the prompt → listen for your spoken answer → speak the answer / grade → advance.
///
/// Every audio failure ends the loop with a message rather than leaving it stuck mid-card:
/// a denied permission, an unavailable recognizer, a failed audio session, or an
/// interruption (a call, another app taking the mic) all stop cleanly.
@MainActor
@Observable
final class VoiceStudyController: NSObject, AVSpeechSynthesizerDelegate {
    let session: StudySession
    var status: String = "Tap start to begin."
    var heard: String = ""
    var isRunning = false
    var permissionDenied = false
    /// A fatal audio/recognition problem, shown in the view.
    var errorText: String?

    private let synth = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var interruptionObserver: NSObjectProtocol?

    private var speakContinuation: CheckedContinuation<Void, Never>?
    private var listenContinuation: CheckedContinuation<String, Never>?
    /// Identifies the current listen, so a stale timeout can't cut a later one short.
    private var listenToken = 0
    private var recognitionError: String?

    init(session: StudySession) {
        self.session = session
        super.init()
        synth.delegate = self
    }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        guard !session.isEmpty else {
            status = "No cards to study."
            return
        }
        errorText = nil
        permissionDenied = false
        isRunning = true
        observeInterruptions()
        Task { await run() }
    }

    func stop() {
        isRunning = false
        synth.stopSpeaking(at: .immediate)
        finishListening()
        resumeSpeak()
        stopObservingInterruptions()
        deactivateSession()
        if errorText == nil { status = "Stopped." }
    }

    /// Ends the run with a reason instead of hanging on a dead microphone.
    private func fail(_ message: String) {
        errorText = message
        status = message
        stop()
    }

    // MARK: - Loop

    private func run() async {
        guard await requestPermissions() else {
            permissionDenied = true
            status = "Microphone or speech permission denied."
            isRunning = false
            stopObservingInterruptions()
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            fail("Speech recognition isn't available on this device or for this language right now.")
            return
        }

        while isRunning, !session.isFinished, let card = session.current {
            switch card.content {
            case .flip(let front, let back):
                await speak(front)
                status = "Listening…"
                _ = await listen(seconds: 5)             // your recall attempt (not judged)
                await speak("The answer is. \(back).")
                await speak("Say got it, or missed.")
                let grade = await listen(seconds: 3)
                guard isRunning else { break }
                session.record(isAffirmative(grade))

            case .multipleChoice(let question, let choices):
                await speak(question)
                await speak(spokenOptions(choices))
                status = "Listening…"
                let said = await listen(seconds: 5)
                guard isRunning else { break }
                let correct = match(said, in: choices)?.isCorrect ?? false
                session.record(correct)
                if said.isEmpty { await speak("I didn't catch that.") }
                let answer = choices.first(where: \.isCorrect)?.text ?? ""
                await speak(correct ? "Correct." : "The answer is. \(answer).")
            }

            guard isRunning else { break }
            session.next()
        }

        if isRunning {
            await speak("Finished. You got \(session.correctCount) of \(session.total) correct.")
            isRunning = false
            status = "Done — \(session.correctCount)/\(session.total) correct."
            stopObservingInterruptions()
        }
        deactivateSession()
    }

    // MARK: - Speech out

    private func speak(_ text: String) async {
        guard isRunning, !text.isEmpty else { return }
        guard activateSession() else { return }
        status = "Speaking…"
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            speakContinuation = cont
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synth.speak(utterance)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeSpeak() }
    }

    /// Without this, stopping mid-sentence would leave `speak` awaiting forever.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeSpeak() }
    }

    private func resumeSpeak() {
        speakContinuation?.resume()
        speakContinuation = nil
    }

    // MARK: - Speech in

    private func listen(seconds: Double) async -> String {
        guard isRunning else { return "" }
        heard = ""                  // never grade this card on the last card's transcript
        recognitionError = nil
        guard startRecognition() else { return "" }

        listenToken += 1
        let token = listenToken
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            listenContinuation = cont
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self, self.listenToken == token else { return }
                self.finishListening()
            }
        }
    }

    private func startRecognition() -> Bool {
        guard let recognizer, recognizer.isAvailable else {
            fail("Speech recognition became unavailable.")
            return false
        }
        guard activateSession() else { return false }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A zero-rate format means the input route is gone (no mic, or it was taken away).
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("No microphone input is available right now.")
            return false
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.request = nil
            fail("Microphone error: \(error.localizedDescription)")
            return false
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result { self.heard = result.bestTranscription.formattedString }
                if let error { self.recognitionError = error.localizedDescription }
            }
        }
        return true
    }

    private func finishListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        let transcript = heard
        // Recognition errors are routine on cancel; only worth mentioning if nothing was heard.
        if transcript.isEmpty, let problem = recognitionError {
            status = "Didn't catch that — \(problem)"
        }
        listenContinuation?.resume(returning: transcript)
        listenContinuation = nil
    }

    // MARK: - Audio session

    @discardableResult
    private func activateSession() -> Bool {
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playAndRecord, mode: .spokenAudio,
                                  options: [.duckOthers, .defaultToSpeaker,
                                            .allowBluetooth, .allowBluetoothA2DP])
            try audio.setActive(true)
            return true
        } catch {
            fail("Audio unavailable: \(error.localizedDescription)")
            return false
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A phone call or another app taking the mic ends the session instead of hanging it.
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.fail("Voice study stopped — audio was interrupted.")
            }
        }
    }

    private func stopObservingInterruptions() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    // MARK: - Parsing helpers

    private func spokenOptions(_ choices: [Choice]) -> String {
        let letters = ["A", "B", "C", "D", "E", "F"]
        return choices.enumerated()
            .map { "\(letters[safe: $0.offset] ?? "Next"). \($0.element.text)." }
            .joined(separator: " ")
    }

    /// Match a spoken answer to a choice by letter ("A"/"B"…) or by text overlap.
    private func match(_ spoken: String, in choices: [Choice]) -> Choice? {
        let said = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        guard !said.isEmpty else { return nil }
        let letters = ["a", "b", "c", "d", "e", "f"]
        for (i, choice) in choices.enumerated() {
            if let letter = letters[safe: i],
               said == letter || said.hasPrefix("\(letter) ") || said.hasPrefix("option \(letter)") {
                return choice
            }
        }
        return choices.first { said.contains($0.text.lowercased()) || $0.text.lowercased().contains(said) }
    }

    private func isAffirmative(_ text: String) -> Bool {
        let said = text.lowercased()
        return ["got it", "yes", "correct", "yeah", "yep", "knew it"].contains { said.contains($0) }
    }

    // MARK: - Permissions

    private func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
