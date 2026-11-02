import AVFoundation
import Foundation
import Observation
import Speech

/// Live speech-to-text using SFSpeechRecognizer + AVAudioEngine.
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

    @ObservationIgnored var onTranscript: ((String) -> Void)?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer? =
        SFSpeechRecognizer(locale: SpeechRecognizer.resolveLocale())
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        ?? SFSpeechRecognizer()
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var sessionID = 0

    private static let audioQueue = DispatchQueue(label: "com.aayushparikh.spaces.speech-audio", qos: .userInitiated)

    nonisolated private static func resolveLocale() -> Locale {
        if let preferred = Locale.preferredLanguages.first, !preferred.isEmpty {
            return Locale(identifier: preferred)
        }
        return Locale(identifier: "en-US")
    }

    private func resolveRecognizer() -> SFSpeechRecognizer? {
        if let recognizer, recognizer.isAvailable {
            return recognizer
        }
        let candidates: [SFSpeechRecognizer?] = [
            SFSpeechRecognizer(locale: Self.resolveLocale()),
            SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
            SFSpeechRecognizer()
        ]
        if let available = candidates.compactMap({ $0 }).first(where: { $0.isAvailable }) {
            self.recognizer = available
            return available
        }
        if let first = candidates.compactMap({ $0 }).first {
            self.recognizer = first
            return first
        }
        return self.recognizer
    }

    func toggle() async {
        if status == .recording { stop() } else { await start() }
    }

    func start(onTranscript: ((String) -> Void)? = nil) async {
        guard status == .idle else { return }
        if let onTranscript {
            self.onTranscript = onTranscript
        }
        errorMessage = nil
        permissionDenied = false
        transcript = ""
        status = .requestingPermission

        guard await Self.requestSpeechAuthorization() else {
            fail("Speech recognition isn’t allowed. Enable it in Settings › Spaces.", denied: true)
            return
        }
        guard await Self.requestMicrophonePermission() else {
            fail("Microphone access isn’t allowed. Enable it in Settings › Spaces.", denied: true)
            return
        }
        guard let recognizer = resolveRecognizer(), recognizer.isAvailable else {
            fail("Speech recognition is unavailable right now.")
            return
        }
        // The user may have cancelled while the permission prompt was showing.
        guard status == .requestingPermission else { return }

        do {
            try await beginSession(with: recognizer)
        } catch {
            teardownAudio(deactivateSession: true)
            fail("Couldn’t start recording: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard status != .idle else { return }
        status = .idle
        teardownAudio(deactivateSession: false)
        request?.endAudio()

        let finishingSession = sessionID
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.sessionID == finishingSession, self.status == .idle else { return }
            if self.task != nil || self.request != nil {
                self.task?.finish()
                self.task?.cancel()
                self.task = nil
                self.request = nil
                Self.deactivateAudioSessionAsync()
            }
        }
    }

    // MARK: - Private

    private func fail(_ message: String, denied: Bool = false) {
        errorMessage = message
        permissionDenied = denied
        status = .idle
    }

    private func beginSession(with recognizer: SFSpeechRecognizer) async throws {
        // Clean up any lingering task or audio tap from a prior session.
        task?.cancel()
        task = nil
        request = nil
        teardownAudio(deactivateSession: false)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        sessionID += 1
        let session = sessionID
        self.request = request
        self.status = .recording

        self.task = Self.startRecognition(recognizer: recognizer, request: request) { [weak self] text, isFinal, error in
            Task { @MainActor in
                self?.handleResult(session: session, text: text, isFinal: isFinal, error: error)
            }
        }

        // Activate AVAudioSession and start AVAudioEngine on a background queue so
        // AVAudioSession_iOS.mm never blocks or warns on the main thread.
        let engine = try await Self.startAudioEngineOffMain(request: request)
        self.audioEngine = engine
    }

    nonisolated private static func startAudioEngineOffMain(
        request: SFSpeechAudioBufferRecognitionRequest
    ) async throws -> AVAudioEngine {
        try await withCheckedThrowingContinuation { continuation in
            audioQueue.async {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.record, mode: .default, options: [])
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                    let engine = AVAudioEngine()
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0 else {
                        throw SpeechError.noInput
                    }

                    installTap(on: input, format: format, request: request)
                    engine.prepare()
                    try engine.start()
                    continuation.resume(returning: engine)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func handleResult(session: Int, text: String?, isFinal: Bool, error: Error?) {
        guard session == sessionID else { return }
        if let text, !text.isEmpty {
            transcript = text
            onTranscript?(text)
        }
        if isFinal || error != nil {
            if status == .recording {
                stop()
            } else {
                Self.deactivateAudioSessionAsync()
            }
            if let error, transcript.isEmpty, !Self.isExplicitCancellation(error) {
                errorMessage = "Couldn’t recognize speech: \(error.localizedDescription)"
            }
            task = nil
            request = nil
        }
    }

    private static func isExplicitCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        // Code 216 / 301 are explicit SFSpeechRecognitionTask cancellation codes.
        return nsError.code == 216 || nsError.code == 301
    }

    private func teardownAudio(deactivateSession: Bool) {
        let engine = audioEngine
        audioEngine = nil
        Self.stopAudioEngineOffMain(engine: engine, deactivateSession: deactivateSession)
    }

    nonisolated private static func stopAudioEngineOffMain(engine: AVAudioEngine?, deactivateSession: Bool) {
        audioQueue.async {
            if let engine {
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
            }
            if deactivateSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    nonisolated private static func deactivateAudioSessionAsync() {
        audioQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // These helpers are `nonisolated` so the audio-thread / recognizer callbacks are
    // NOT inferred to be main-actor isolated (which would trap at runtime).

    nonisolated private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat,
                                               request: SFSpeechAudioBufferRecognitionRequest) {
        node.removeTap(onBus: 0)
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

    nonisolated private static func requestMicrophonePermission() async -> Bool {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        @unknown default:
            return await AVAudioApplication.requestRecordPermission()
        }
    }
}
