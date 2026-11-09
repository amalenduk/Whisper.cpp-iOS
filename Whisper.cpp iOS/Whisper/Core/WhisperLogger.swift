//
//  WhisperLogger.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation
@_exported import os

/// Unified, high-performance logging subsystem for Whisper.cpp iOS.
///
/// Easily inspect and filter logs in Xcode Console or macOS Console.app using:
/// `subsystem: com.whisper.ios` (or your app's bundle ID)
/// Categories: `Audio`, `Converter`, `VAD`, `LiveTranscription`, `Inference`, `App`
nonisolated enum WhisperLog {
    
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.whisper.ios"
    
    /// Audio capture, AVAudioEngine, real-time tap, ring buffer, interruptions, route changes
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    
    /// Sample rate and channel format conversion (AVAudioConverter)
    static let converter = Logger(subsystem: subsystem, category: "Converter")
    
    /// Voice activity detection, speech energy thresholds, RMS, speech start/end
    static let vad = Logger(subsystem: subsystem, category: "VAD")
    
    /// Live transcription service, phrase accumulation, buffer windowing, backlogs
    static let live = Logger(subsystem: subsystem, category: "LiveTranscription")
    
    /// Low-level Whisper.cpp context, model loading, whisper_full inference timing
    static let inference = Logger(subsystem: subsystem, category: "Inference")
    
    /// ViewModel and UI state transitions
    static let app = Logger(subsystem: subsystem, category: "App")
}
