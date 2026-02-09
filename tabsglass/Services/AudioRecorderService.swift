//
//  AudioRecorderService.swift
//  tabsglass
//
//  Voice recording service for composer
//

import AVFoundation
import Foundation

@MainActor
final class AudioRecorderService: NSObject {
    private(set) var isRecording = false

    var onElapsedChange: ((TimeInterval) -> Void)?
    var onAutoStop: ((RecordedVoiceDraft?) -> Void)?

    private var recorder: AVAudioRecorder?
    private var progressTimer: Timer?
    private var recordingStartDate: Date?
    private let maxDuration: TimeInterval

    init(maxDuration: TimeInterval = 180) {
        self.maxDuration = maxDuration
        super.init()
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func startRecording() throws {
        stopTimer()
        try configureAudioSessionForRecording()

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 64_000
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw NSError(domain: "AudioRecorderService", code: 1)
        }

        self.recorder = recorder
        self.recordingStartDate = Date()
        self.isRecording = true
        startTimer()
        onElapsedChange?(0)
    }

    func stopRecording() -> RecordedVoiceDraft? {
        guard let recorder else { return nil }

        let elapsedSinceStart = max(
            recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0,
            0
        )
        let url = recorder.url
        recorder.stop()
        stopTimer()

        let recorderDuration = max(recorder.currentTime, 0)
        let fileDuration = SharedAudioStorage.audioDuration(at: url)
        let resolvedDuration = max(recorderDuration, elapsedSinceStart, fileDuration)

        self.recorder = nil
        self.recordingStartDate = nil
        self.isRecording = false
        deactivateAudioSessionLater()

        // Keep very short accidental taps from becoming drafts.
        guard resolvedDuration >= 0.15 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return RecordedVoiceDraft(fileURL: url, duration: resolvedDuration)
    }

    func cancelRecording() {
        if let recorder {
            let url = recorder.url
            recorder.stop()
            try? FileManager.default.removeItem(at: url)
        }

        stopTimer()
        self.recorder = nil
        self.recordingStartDate = nil
        self.isRecording = false
        onElapsedChange?(0)
        deactivateAudioSessionLater()
    }

    private func configureAudioSessionForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }

    private func deactivateAudioSession() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func deactivateAudioSessionLater() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            try? deactivateAudioSession()
        }
    }

    private func startTimer() {
        stopTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard let startedAt = self.recordingStartDate, let recorder = self.recorder else { return }

                let elapsed = max(Date().timeIntervalSince(startedAt), 0)
                self.onElapsedChange?(elapsed)

                if elapsed >= self.maxDuration {
                    let draft = self.stopRecording()
                    self.onAutoStop?(draft)
                } else if recorder.currentTime >= self.maxDuration {
                    let draft = self.stopRecording()
                    self.onAutoStop?(draft)
                }
            }
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            self?.cancelRecording()
        }
    }
}
