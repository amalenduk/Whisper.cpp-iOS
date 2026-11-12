//
//  SpeechLogger.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 12/11/26.
//

import Foundation
@_exported import os

public enum SpeechLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.akplayer.speech"
    
    public static let recorder = Logger(subsystem: subsystem, category: "Recorder")
    public static let transcriber = Logger(subsystem: subsystem, category: "Transcriber")
    public static let legacy = Logger(subsystem: subsystem, category: "LegacySpeech")
    public static let modern = Logger(subsystem: subsystem, category: "ModernSpeech")
    public static let viewModel = Logger(subsystem: subsystem, category: "ViewModel")
}
