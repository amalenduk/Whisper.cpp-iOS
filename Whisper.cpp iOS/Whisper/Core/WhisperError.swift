//
//  WhisperError.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

enum WhisperError: LocalizedError, Sendable {
    case modelNotFound(URL)
    case couldNotInitializeContext
    case emptyAudio
    case audioContainsInvalidSamples
    case audioTooLong
    case transcriptionFailed(Int32)
    case invalidSegmentText

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let url):
            return "Whisper model not found at: \(url.path)"

        case .couldNotInitializeContext:
            return "Failed to initialize Whisper context."

        case .emptyAudio:
            return "Audio samples are empty."

        case .audioContainsInvalidSamples:
            return "Audio contains invalid floating-point samples."

        case .audioTooLong:
            return "Audio sample count exceeds Whisper's supported limit."

        case .transcriptionFailed(let code):
            return "Whisper transcription failed with code: \(code)."

        case .invalidSegmentText:
            return "Whisper returned an invalid transcription segment."
        }
    }
}
