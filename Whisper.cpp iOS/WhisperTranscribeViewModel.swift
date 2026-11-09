//
//  WhisperTranscribeViewModel.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation
import SwiftUI
import whisper

@MainActor
@Observable
final class WhisperTranscribeViewModel {
    
    private var whisperContext: WhisperContext?
    private var recorder: WhisperAudioRecorder?
    private var converter: WhisperAudioConverter?
    private var transcriptionService: WhisperLiveTranscriptionService?
    
    private var transcriptionTask: Task<Void, Never>?
    
    // MARK: - State Properties
    public var transcriptionResult: WhisperLiveTranscriptionResult?
    public var isRecording: Bool = false
    public var isStopping: Bool = false
    public var isPreparing: Bool = false
    public var errorMessage: String? = nil
    
    public let supportedLocales: [(code: String?, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("hi", "Hindi"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("bn", "Bengali"),
        (nil, "Auto Detect")
    ]
    
    // Convenience getters for UI
    public var fullTranscript: String {
        transcriptionResult?.transcript ?? ""
    }
    
    public var partialText: String {
        transcriptionResult?.partialText ?? ""
    }
    
    public var finalizedText: String {
        transcriptionResult?.finalizedText ?? ""
    }
    
    public var detectedLanguage: String? {
        transcriptionResult?.detectedLanguage
    }
    
    public var selectedLocale: String? = "en"
    
    init() { }
    
    func prepare() {
        guard whisperContext == nil else { return }
        isPreparing = true
        errorMessage = nil
        
        do {
            whisperContext = try WhisperContext.createContext()
            recorder = WhisperAudioRecorder()
            converter = try WhisperAudioConverter()
            
            let configuration = WhisperConfiguration(
                language: selectedLocale
            )
            
            transcriptionService = WhisperLiveTranscriptionService(
                recorder: recorder!,
                converter: converter!,
                whisperContext: whisperContext!,
                configuration: configuration
            )
            isPreparing = false
            WhisperLog.app.info("Whisper model and audio services successfully initialized.")
        } catch {
            isPreparing = false
            errorMessage = "Failed to initialize Whisper: \(error.localizedDescription)"
            WhisperLog.app.error("Error while preparing Whisper: \(error.localizedDescription)")
        }
    }
    
    func start() {
        guard !isRecording, !isStopping else { return }
        WhisperLog.app.info("Starting live transcription from UI...")
        errorMessage = nil
        
        if transcriptionService == nil {
            prepare()
        }
        
        guard let transcriptionService else {
            if errorMessage == nil {
                errorMessage = "Transcription service is not initialized."
            }
            WhisperLog.app.error("Cannot start: transcriptionService is nil.")
            return
        }
        
        isRecording = true
        
        transcriptionTask = Task {
            do {
                let stream = try await transcriptionService.start()
                
                for try await result in stream {
                    guard !Task.isCancelled else { break }
                    self.transcriptionResult = result
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    WhisperLog.app.error("Transcription stream error: \(error.localizedDescription)")
                }
            }
            self.isRecording = false
        }
    }
    
    func stop() {
        guard isRecording, !isStopping else { return }
        WhisperLog.app.info("Stopping live transcription from UI...")
        
        isStopping = true
        isRecording = false
        
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        Task {
            await transcriptionService?.stop()
            self.isStopping = false
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stop()
        } else if !isStopping {
            start()
        }
    }
    
    func clearTranscript() {
        transcriptionResult = nil
        errorMessage = nil
        Task {
            await transcriptionService?.clearTranscript()
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Locale Update & Restart
    
    func updateLocaleAndRestart(newLocale: String?) {
        Task {
            selectedLocale = newLocale
            let wasRecording = isRecording
            if wasRecording {
                stop()
                // Brief pause to allow audio engine & tasks to drain
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            
            await transcriptionService?.updateLanguage(newLocale)
            
            if wasRecording {
                start()
            }
        }
    }
}

