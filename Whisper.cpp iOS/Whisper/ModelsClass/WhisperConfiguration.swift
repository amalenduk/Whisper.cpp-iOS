//
//  WhisperConfiguration.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

nonisolated struct WhisperConfiguration: Sendable {
    
    // MARK: - General & Language
    
    /// Spoken language code (e.g. "en", "es", "hi").
    /// Use nil for automatic language detection.
    let language: String?
    
    /// Whether Whisper should translate recognized speech into English.
    let translateToEnglish: Bool
    
    // MARK: - Compute / Threads
    
    /// Number of CPU threads used for inference.
    /// Nil automatically detects the optimal count based on device performance cores.
    let threadCount: Int?
    
    /// Whether to process each audio chunk independently without prior text context.
    /// True is standard and recommended for live streaming to avoid runaway hallucination loops.
    let noContext: Bool
    
    /// Whether to return one segment for the complete audio chunk.
    let singleSegment: Bool
    
    // MARK: - Whisper Decoder Parameters
    
    /// Decoding temperature (0.0 for deterministic, greedy decoding).
    let temperature: Float
    
    /// Threshold for internal non-speech rejection (standard Whisper default is 0.6).
    let noSpeechThreshold: Float
    
    /// Average log-probability threshold for token acceptance (standard Whisper default is -1.0).
    let logprobThreshold: Float
    
    /// Suppresses blank tokens at the start of transcription.
    let suppressBlank: Bool
    
    /// Suppresses non-speech tokens (e.g. musical notes, applause symbols).
    let suppressNonSpeechTokens: Bool
    
    // MARK: - Audio VAD (Voice Activity Detection) Parameters
    
    /// Minimum RMS audio energy considered speech.
    /// 0.008 (~ -42 dBFS) allows natural, soft conversational speaking without needing to shout.
    let vadSpeechThreshold: Float
    
    /// Duration of silence (in seconds) required to mark the end of a spoken phrase.
    /// 0.85s matches standard natural conversational pauses.
    let vadSilenceDuration: TimeInterval
    
    // MARK: - Initializer
    
    init(
        language: String? = nil,
        translateToEnglish: Bool = false,
        threadCount: Int? = nil,
        noContext: Bool = true,
        singleSegment: Bool = false,
        temperature: Float = 0.0,
        noSpeechThreshold: Float = 0.6,
        logprobThreshold: Float = -1.0,
        suppressBlank: Bool = true,
        suppressNonSpeechTokens: Bool = true,
        vadSpeechThreshold: Float = 0.008,
        vadSilenceDuration: TimeInterval = 0.85
    ) {
        self.language = language
        self.translateToEnglish = translateToEnglish
        self.threadCount = threadCount
        self.noContext = noContext
        self.singleSegment = singleSegment
        self.temperature = temperature
        self.noSpeechThreshold = noSpeechThreshold
        self.logprobThreshold = logprobThreshold
        self.suppressBlank = suppressBlank
        self.suppressNonSpeechTokens = suppressNonSpeechTokens
        self.vadSpeechThreshold = vadSpeechThreshold
        self.vadSilenceDuration = vadSilenceDuration
    }
    
    /// Dynamically determines optimal thread count (typically 4 threads on iOS devices).
    var resolvedThreadCount: Int {
        let availableThreads = max(
            2,
            min(6, ProcessInfo.processInfo.processorCount - 2)
        )
        
        guard let threadCount else {
            return availableThreads
        }
        
        return max(1, min(threadCount, availableThreads))
    }
    
    static let `default`: WhisperConfiguration = WhisperConfiguration()
}
