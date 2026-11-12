//
//  LegacySpeechTranscriber.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 12/11/26.
//

import AVFoundation
import Foundation
import Speech

public enum LegacyTranscriptionError: LocalizedError {
    case speechRecognitionDenied
    case speechRecognitionRestricted
    case recognizerUnavailable
    case recognitionRequestFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .speechRecognitionDenied:
            return "Speech recognition permission was denied. Please allow it in Settings."
        case .speechRecognitionRestricted:
            return "Speech recognition is restricted on this device."
        case .recognizerUnavailable:
            return "Speech recognizer is currently unavailable for the chosen language."
        case .recognitionRequestFailed(let reason):
            return "Speech recognition failed: \(reason)"
        }
    }
}

@Observable
@MainActor
public final class LegacySpeechTranscriber: SpeechTranscriptionService {
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Published states for UI
    public var finalizedText: String = ""
    public var volatileText: String = ""
    public var tokens: [SpeechTranscriptionToken] = []
    public var downloadProgress: Progress? = nil
    public var isDownloadingModel: Bool = false
    
    public var engineDescription: String {
        "Apple SFSpeechRecognizer (iOS 17+)"
    }
    
    public var fullTranscript: String {
        let first = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        return first + " " + second
    }
    
    public init() {}
    
    public func setUpTranscriber(locale: Locale) async throws {
        // 1. Verify Speech Recognition Authorization
        let status = await requestSpeechAuthorization()
        guard status == .authorized else {
            if status == .restricted {
                throw LegacyTranscriptionError.speechRecognitionRestricted
            } else {
                throw LegacyTranscriptionError.speechRecognitionDenied
            }
        }
        
        // 2. Resolve matching locale
        let availableLocales = Array(SFSpeechRecognizer.supportedLocales())
        let availableIDs = availableLocales.map { $0.identifier }
        let resolvedID = SpeechLocaleHelper.findBestMatchingLocale(
            for: locale.identifier,
            in: availableIDs
        )
        let targetLocale = Locale(identifier: resolvedID)
        
        guard let recognizer = SFSpeechRecognizer(locale: targetLocale), recognizer.isAvailable else {
            throw LegacyTranscriptionError.recognizerUnavailable
        }
        self.speechRecognizer = recognizer
        
        // 3. Configure audio buffer recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        
        // Enable on-device recognition when available to minimize latency
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            request.requiresOnDeviceRecognition = false
        }
        self.recognitionRequest = request
        
        // 4. Start recognition task
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            
            if let result {
                let formatted = result.bestTranscription.formattedString
                let segmentTokens = result.bestTranscription.segments.map { seg in
                    SpeechTranscriptionToken(
                        text: seg.substring,
                        confidence: seg.confidence,
                        timestamp: seg.timestamp,
                        duration: seg.duration
                    )
                }
                self.tokens = segmentTokens
                
                if result.isFinal {
                    let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if self.finalizedText.isEmpty {
                            self.finalizedText = trimmed
                        } else {
                            self.finalizedText += " " + trimmed
                        }
                    }
                    self.volatileText = ""
                } else {
                    self.volatileText = formatted
                }
            }
            
            if let error {
                SpeechLog.legacy.debug("SFSpeechRecognizer task notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Streams audio buffer directly to SFSpeechAudioBufferRecognitionRequest with zero conversion overhead
    public func streamAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let request = recognitionRequest else {
            throw LegacyTranscriptionError.recognitionRequestFailed("No active recognition session.")
        }
        request.append(buffer)
    }
    
    public func finishTranscribing() async throws {
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Allow in-flight partial results to settle
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        recognitionTask?.finish()
        recognitionTask = nil
    }
    
    public func clear() {
        finalizedText = ""
        volatileText = ""
        tokens = []
    }
    
    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

