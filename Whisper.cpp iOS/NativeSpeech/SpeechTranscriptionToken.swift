//
//  SpeechTranscriptionToken.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 12/11/26.
//

import Foundation

public struct SpeechTranscriptionToken: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let text: String
    public let confidence: Float
    public let timestamp: TimeInterval
    public let duration: TimeInterval
    
    public init(
        id: UUID = UUID(),
        text: String,
        confidence: Float = 1.0,
        timestamp: TimeInterval = 0.0,
        duration: TimeInterval = 0.0
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.timestamp = timestamp
        self.duration = duration
    }
}

