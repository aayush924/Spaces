import AVFoundation
import Foundation
import Observation
import Speech

/// Live speech-to-text using SFSpeechRecognizer + AVAudioEngine.
/// Uses on-device recognition when the recognizer supports it.
@MainActor
@Observable
final class SpeechRecognizer {
    enum Status: Equatable {
        case idle
        case requestingPermission
        case recording
    }

    private enum SpeechError: LocalizedError {
        case noInput
        var errorDescription: String? { "No microphone input is available." }
    }

    /// Live (partial, then final) transcript of the current/last session.
    private(set) var transcript = ""
    private(set) var status: Status = .idle
    /// User-facing problem (permissions, unavailable recognizer, audio errors).
    var errorMessage: String?
    /// True when the user denied mic or speech permission (offer a link to Settings).
    private(set) var permissionDenied = false

    var isRecording: Bool { status == .recording }

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var sessionID = 0
    @ObservationIgnored private let recognizer: SFSpeechRecognizer? =
        SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func toggle() async {
        if status == .recording { stop() } else { await start() }
    }

    func start() async {
        guard status == .idle else { return }
        errorMessage = nil
        permissionDenied = false
        transcript = ""
        status = .requestingPermission

        guard await Self.requestSpeechAuthorization() else {
            fail("Speech recognition isn’t allowed. Enable it in Settings › Spaces.", denied: true)
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            fail("Microphone access isn’t allowed. Enable it in Settings › Spaces.", denied: true)
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            fail("Speech recognition is unavailable right now.")
            return
        }
        // The user may have cancelled while the permission prompt was showing.
        guard status == .requestingPermission else { return }

        do {
            try beginSession(with: recognizer)
            status = .recording
        } catch {
            teardownAudio()
            fail("Couldn’t start recording: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard status != .idle else { return }
        status = .idle
        request?.endAudio()
        task?.finish() // lets the recognizer deliver a final result
        teardownAudio()
    }

    // MARK: - Private

    private func fail(_ message: String, denied: Bool = false) {
        errorMessage = message
        permissionDenied = denied
        status = .idle
    }

    private func beginSession(with recognizer: SFSpeechRecognizer) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechError.noInput }

        Self.installTap(on: input, format: format, request: request)
        engine.prepare()
        try engine.start()

        sessionID += 1
        let session = sessionID
        self.audioEngine = engine
        self.request = request
        self.task = Self.startRecognition(recognizer: recognizer, request: request) { [weak self] text, isFinal, error in
            Task { @MainActor in
                self?.handleResult(session: session, text: text, isFinal: isFinal, error: error)
            }
        }
    }

    private func handleResult(session: Int, text: String?, isFinal: Bool, error: Error?) {
        guard session == sessionID else { return }
        if let text { transcript = text }
        if isFinal || error != nil {
            if status == .recording { stop() }
            task = nil
            request = nil
        }
    }

    private func teardownAudio() {
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // These helpers are `nonisolated` so the audio-thread / recognizer callbacks are
    // NOT inferred to be main-actor isolated (which would trap at runtime).

    nonisolated private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat,
                                               request: SFSpeechAudioBufferRecognitionRequest) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func startRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Bool, Error?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error)
        }
    }

    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }
}
