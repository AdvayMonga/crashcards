import Foundation
import AVFoundation
import Speech
import Observation

/// Drives a hands-free voice study loop over a `StudySession`:
/// speak the prompt → listen for your spoken answer → speak the answer / grade → advance.
@MainActor
@Observable
final class VoiceStudyController: NSObject, AVSpeechSynthesizerDelegate {
    let session: StudySession
    var status: String = "Tap start to begin."
    var heard: String = ""
    var isRunning = false
    var permissionDenied = false

    private let synth = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var speakContinuation: CheckedContinuation<Void, Never>?
    private var listenContinuation: CheckedContinuation<String, Never>?

    init(session: StudySession) {
        self.session = session
        super.init()
        synth.delegate = self
    }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Task { await run() }
    }

    func stop() {
        isRunning = false
        synth.stopSpeaking(at: .immediate)
        finishListening()
        resumeSpeak()
        deactivateSession()
        status = "Stopped."
    }

    // MARK: - Loop

    private func run() async {
        guard await requestPermissions() else {
            permissionDenied = true
            status = "Microphone or speech permission denied."
            isRunning = false
            return
        }

        while isRunning, !session.isFinished, let card = session.current {
            switch card.content {
            case .flip(let front, let back):
                await speak(front)
                status = "Listening…"
                heard = await listen(seconds: 5)          // your recall attempt (not judged)
                await speak("The answer is. \(back).")
                await speak("Say got it, or missed.")
                let grade = await listen(seconds: 3)
                session.record(isAffirmative(grade))

            case .multipleChoice(let question, let choices):
                await speak(question)
                await speak(spokenOptions(choices))
                status = "Listening…"
                heard = await listen(seconds: 5)
                let correct = match(heard, in: choices)?.isCorrect ?? false
                session.record(correct)
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
        }
        deactivateSession()
    }

    // MARK: - Speech out

    private func speak(_ text: String) async {
        guard isRunning else { return }
        status = "Speaking…"
        activateSession()
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

    private func resumeSpeak() {
        speakContinuation?.resume()
        speakContinuation = nil
    }

    // MARK: - Speech in

    private func listen(seconds: Double) async -> String {
        guard isRunning, startRecognition() else { return "" }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            listenContinuation = cont
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.finishListening()
            }
        }
    }

    private func startRecognition() -> Bool {
        activateSession()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            status = "Mic error: \(error.localizedDescription)"
            return false
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            Task { @MainActor in self.heard = result.bestTranscription.formattedString }
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
        listenContinuation?.resume(returning: transcript)
        listenContinuation = nil
    }

    // MARK: - Audio session

    private func activateSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .spokenAudio,
                               options: [.duckOthers, .defaultToSpeaker,
                                         .allowBluetooth, .allowBluetoothA2DP])
        try? audio.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Parsing helpers

    private func spokenOptions(_ choices: [Choice]) -> String {
        let letters = ["A", "B", "C", "D", "E", "F"]
        return choices.enumerated()
            .map { "\(letters[safe: $0.offset] ?? "Option"). \($0.element.text)." }
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
