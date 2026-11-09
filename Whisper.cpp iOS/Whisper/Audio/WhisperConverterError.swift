//
//  WhisperConverterError.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

enum WhisperConverterError: LocalizedError, Sendable {

    case invalidSampleRate
    case invalidAudioSamples
    case audioTooLong
    case converterUnavailable

    case couldNotCreateInputFormat
    case couldNotCreateOutputFormat
    case couldNotCreateConverter

    case couldNotCreateInputBuffer
    case couldNotCreateOutputBuffer

    case invalidInputBuffer
    case invalidOutputBuffer

    case conversionFailed(String)

    var errorDescription: String? {

        switch self {

        case .invalidSampleRate:
            return "The input audio sample rate is invalid."

        case .invalidAudioSamples:
            return "The input audio contains invalid samples."

        case .audioTooLong:
            return "The audio chunk is too large to convert."

        case .converterUnavailable:
            return "The audio converter is unavailable."

        case .couldNotCreateInputFormat:
            return "Could not create the input audio format."

        case .couldNotCreateOutputFormat:
            return "Could not create the output audio format."

        case .couldNotCreateConverter:
            return "Could not create the audio converter."

        case .couldNotCreateInputBuffer:
            return "Could not create the input audio buffer."

        case .couldNotCreateOutputBuffer:
            return "Could not create the output audio buffer."

        case .invalidInputBuffer:
            return "The input audio buffer is invalid."

        case .invalidOutputBuffer:
            return "The output audio buffer is invalid."

        case .conversionFailed(let message):
            return "Audio conversion failed: \(message)"
        }
    }
}
