//
//  WhisperLiveTranscriptionResult.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

nonisolated struct WhisperLiveTranscriptionResult: Sendable {

    /// All committed text, plus the current partial phrase.
    let transcript: String

    /// Current provisional phrase. Empty when no partial is available.
    let partialText: String

    /// Newly committed phrase. Empty for partial updates.
    let finalizedText: String

    /// Detected language code, for example "en", "hi", or "bn".
    let detectedLanguage: String?

    /// True when this update represents a finalized phrase.
    let isFinal: Bool

    /// Segments returned by Whisper for this update.
    let segments: [WhisperSegment]
}
