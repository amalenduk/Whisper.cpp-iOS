//
//  WhisperBufferError.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

enum WhisperBufferError: LocalizedError, Sendable {

    case invalidAudioSamples
    case maximumDurationExceeded

    var errorDescription: String? {

        switch self {

        case .invalidAudioSamples:
            return "The audio buffer contains invalid samples."

        case .maximumDurationExceeded:
            return "The maximum audio buffer duration was exceeded."
        }
    }
}
