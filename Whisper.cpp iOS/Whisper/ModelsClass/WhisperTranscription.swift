//
//  WhisperTranscription.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

nonisolated struct WhisperSegment: Sendable, Identifiable {

    let id: Int
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

nonisolated struct WhisperTranscription: Sendable {

    /// Complete recognized text in the original spoken language.
    let text: String

    /// Individual recognized segments and their timestamps.
    let segments: [WhisperSegment]

    /// Duration of the audio supplied to Whisper.
    let duration: TimeInterval

    /// Detected language code, such as "en", "hi", or "bn".
    let detectedLanguage: String?
}
