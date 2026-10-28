import AVFoundation
import Foundation
import Speech

/// Records from the microphone and transcribes with Apple's on-device speech recognizer.
/// Server recognition is never requested. Audio stays in this process until recognition returns text.
final class OnDeviceSpeechListener {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private(set) var transcript = ""
    private var sawFailure = false

    static var recognizerAvailable: Bool {
        SFSpeechRecognizer()?.isAvailable == true
    }

    static func capabilityLine() -> String {
        let recognizer = SFSpeechRecognizer()
        let locale = recognizer?.locale.identifier ?? "none"
        let available = recognizer?.isAvailable == true
        return "onDeviceRequired=true locale=\(locale) available=\(available) speechStatus=\(SFSpeechRecognizer.authorizationStatus().rawValue) microphone=\(AVAudioApplication.shared.recordPermission.rawValue)"
    }

    static var permissionsGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static func requestAccess(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { microphoneGranted in
            guard microphoneGranted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { completion(status == .authorized) }
            }
        }
    }

    /// Starts a fresh on-device session. Throws when the recognizer or input device cannot be used locally.
    func start() throws {
        cancel()
        transcript = ""
        sawFailure = false
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw ListenError.unavailable
        }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { self.transcript = trimmed }
            }
            if error != nil { self.sawFailure = true }
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ListenError.noInput }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    /// Ends audio and waits briefly so the recognizer can emit its last partial result.
    func stop(completion: @escaping (Result<String, ListenError>) -> Void) {
        request?.endAudio()
        stopEngine()
        let started = Date()
        func finish() {
            let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let failed = sawFailure
            cancel()
            if words.isEmpty && failed {
                completion(.failure(.unavailable))
            } else {
                completion(.success(words))
            }
        }
        func wait() {
            let done = task?.state == .completed || task?.state == .canceling
            if done || Date().timeIntervalSince(started) > 0.8 {
                finish()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: wait)
            }
        }
        wait()
    }

    func cancel() {
        stopEngine()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        transcript = ""
        sawFailure = false
    }

    private func stopEngine() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
    }
}

enum ListenError: Error {
    case unavailable
    case noInput

    var note: String {
        switch self {
        case .unavailable:
            return "On-device speech recognition isn't available. Cleo will not send audio to a server."
        case .noInput:
            return "Cleo couldn't open the microphone."
        }
    }
}
