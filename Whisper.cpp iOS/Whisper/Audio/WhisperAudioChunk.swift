//
//  WhisperAudioChunk.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

/// Represents a captured microphone audio chunk.
///
/// Samples are mono Float32 audio at the original hardware sample rate.
/// Resampling is performed separately by `WhisperAudioConverter`.
nonisolated struct WhisperAudioChunk: Sendable {

    /// Mono audio samples.
    let samples: [Float]

    /// Actual sample rate of the captured audio.
    let sampleRate: Double

    /// Monotonic capture timestamp.
    let timestamp: TimeInterval

    /// Number of captured audio frames.
    var frameCount: Int {
        samples.count
    }

    /// Duration of this audio chunk.
    var duration: TimeInterval {
        Double(samples.count) / sampleRate
    }
}
