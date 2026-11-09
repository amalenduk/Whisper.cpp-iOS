//
//  WhisperRecorderError.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

enum WhisperRecorderError: LocalizedError, Sendable {

    case alreadyRecording
    case microphonePermissionDenied
    case invalidAudioFormat
    case unsupportedAudioFormat
    case recordingFailed(String)
    case interrupted

    var errorDescription: String? {

        switch self {

        case .alreadyRecording:
            return "Audio recording is already running."

        case .microphonePermissionDenied:
            return "Microphone permission was denied."

        case .invalidAudioFormat:
            return "The microphone returned an invalid audio format."

        case .unsupportedAudioFormat:
            return "The microphone audio format is not supported."

        case .recordingFailed(let message):
            return "Audio recording failed: \(message)"
        case .interrupted:
            return "Audio recording was interrupted (e.g. phone call or route change)."
        }
    }
}
