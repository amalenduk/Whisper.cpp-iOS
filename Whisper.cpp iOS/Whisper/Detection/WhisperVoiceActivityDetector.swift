//
//  WhisperVoiceActivityDetector.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

nonisolated struct WhisperVoiceActivity: Sendable {

    let isSpeechActive: Bool
    let didStartSpeech: Bool
    let didEndSpeech: Bool
    let energy: Float
}

nonisolated struct WhisperVoiceActivityDetector: Sendable {

    // MARK: - Configuration

    /// Minimum RMS energy considered speech (0.008 ~ -42 dBFS allows soft/normal voice without shouting).
    var speechThreshold: Float = 0.008

    /// Silence duration required to finish a speech phrase.
    var silenceDuration: TimeInterval = 0.85

    /// Minimum speech duration required to accept a phrase.
    var minimumSpeechDuration: TimeInterval = 0.15

    // MARK: - Initializer

    init(
        speechThreshold: Float = 0.008,
        silenceDuration: TimeInterval = 0.85,
        minimumSpeechDuration: TimeInterval = 0.15
    ) {
        self.speechThreshold = speechThreshold
        self.silenceDuration = silenceDuration
        self.minimumSpeechDuration = minimumSpeechDuration
    }

    // MARK: - State

    private(set) var isSpeechActive = false

    private var accumulatedSpeechDuration: TimeInterval = 0
    private var accumulatedSilenceDuration: TimeInterval = 0

    // MARK: - Processing

    mutating func process(
        samples: [Float],
        sampleRate: Double
    ) -> WhisperVoiceActivity {

        guard !samples.isEmpty,
              sampleRate.isFinite,
              sampleRate > 0 else {

            return WhisperVoiceActivity(
                isSpeechActive: isSpeechActive,
                didStartSpeech: false,
                didEndSpeech: false,
                energy: 0
            )
        }

        let duration = Double(samples.count) / sampleRate
        let energy = calculateRMS(samples)

        let containsSpeech = energy >= speechThreshold

        var didStartSpeech = false
        var didEndSpeech = false

        if containsSpeech {

            accumulatedSpeechDuration += duration
            accumulatedSilenceDuration = 0

            if !isSpeechActive {
                isSpeechActive = true
                didStartSpeech = true
                let threshold = speechThreshold
                WhisperLog.vad.info("Speech STARTED (RMS: \(String(format: "%.4f", energy)) >= threshold \(String(format: "%.4f", threshold)))")
            }

        } else {

            accumulatedSilenceDuration += duration

            if accumulatedSilenceDuration >= silenceDuration {

                if isSpeechActive {
                    isSpeechActive = false
                    didEndSpeech = true
                    let silence = accumulatedSilenceDuration
                    WhisperLog.vad.info("Speech ENDED (accumulated silence: \(String(format: "%.2f", silence))s, final RMS: \(String(format: "%.4f", energy)))")
                }

                accumulatedSpeechDuration = 0
                accumulatedSilenceDuration = 0
            }
        }

        return WhisperVoiceActivity(
            isSpeechActive: isSpeechActive,
            didStartSpeech: didStartSpeech,
            didEndSpeech: didEndSpeech,
            energy: energy
        )
    }

    // MARK: - Reset

    mutating func reset() {

        isSpeechActive = false
        accumulatedSpeechDuration = 0
        accumulatedSilenceDuration = 0
    }

    // MARK: - Private

    private func calculateRMS(_ samples: [Float]) -> Float {

        guard !samples.isEmpty else {
            return 0
        }

        let sumOfSquares = samples.reduce(Float.zero) {
            $0 + ($1 * $1)
        }

        return sqrt(sumOfSquares / Float(samples.count))
    }
}
