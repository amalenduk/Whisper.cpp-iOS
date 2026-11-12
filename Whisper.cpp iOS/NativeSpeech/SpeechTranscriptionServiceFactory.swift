//
//  SpeechTranscriptionServiceFactory.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 12/11/26.
//

import Foundation

@MainActor
public enum SpeechTranscriptionServiceFactory {
    
    /// Creates the appropriate transcription service based on iOS runtime capabilities.
    /// iOS 26+: ModernSpeechTranscriber (SpeechAnalyzer / SpeechTranscriber)
    /// iOS 17-25: LegacySpeechTranscriber (SFSpeechRecognizer)
    public static func makeService(forceLegacy: Bool = false) -> any SpeechTranscriptionService {
        if #available(iOS 26.0, macOS 26.0, *), !forceLegacy {
            return ModernSpeechTranscriber()
        } else {
            return LegacySpeechTranscriber()
        }
    }
}

