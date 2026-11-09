//
//  WhisperAudioBuffer.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

// This buffer holds the current phrase until VAD detects silence.
// It has a maximum duration so an uninterrupted recording cannot grow indefinitely.
nonisolated struct WhisperAudioBuffer: Sendable {
    
    // MARK: - Properties
    
    let sampleRate: Double
    
    let maximumDuration: TimeInterval
    
    private(set) var samples: [Float] = []
    
    // MARK: - Initialization
    
    init(
        sampleRate: Double = 16_000,
        maximumDuration: TimeInterval = 30
    ) {
        self.sampleRate = sampleRate
        self.maximumDuration = maximumDuration
        
        let capacity = Int(sampleRate * maximumDuration)
        samples.reserveCapacity(capacity)
    }
    
    // MARK: - Buffer Management
    
    mutating func append(_ newSamples: [Float]) throws {
        
        guard !newSamples.isEmpty else {
            return
        }
        
        guard newSamples.allSatisfy(\.isFinite) else {
            throw WhisperBufferError.invalidAudioSamples
        }
        
        let maximumSamples = Int(sampleRate * maximumDuration)
        
        guard newSamples.count <= maximumSamples - samples.count else {
            throw WhisperBufferError.maximumDurationExceeded
        }
        
        samples.append(contentsOf: newSamples)
    }
    
    /// Returns a snapshot without modifying the underlying buffer.
    func snapshot() -> [Float] {
        samples
    }
    
    /// Current buffered audio duration.
    var duration: TimeInterval {
        Double(samples.count) / sampleRate
    }
    
    var isEmpty: Bool {
        samples.isEmpty
    }
    
    /// Releases the current phrase audio.
    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}
