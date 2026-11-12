//
//  NativeSpeechViewModel.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import AVFoundation
import Foundation
import os
import SwiftUI

@Observable
@MainActor
final class NativeSpeechViewModel {
    
    private let recorder: NativeSpeechRecorder
    private(set) var transcriber: any SpeechTranscriptionService
    
    private var streamingTask: Task<Void, Never>?
    
    // Engine Selection State
    var selectedEngineMode: SpeechEngineMode {
        didSet {
            SpeechLog.viewModel.info("Switched to engine: \(self.selectedEngineMode.rawValue)")
        }
    }
    
    var isModernEngineSupported: Bool {
        SpeechLocaleHelper.isModernSupported
    }
    
    /// Two-way toggle property for UI binding
    var isUsingModernEngine: Bool {
        get {
            selectedEngineMode == .modern
        }
        set {
            let targetMode: SpeechEngineMode = newValue ? .modern : .legacy
            switchEngine(to: targetMode)
        }
    }
    
    // UI State Properties
    var isRecording: Bool = false
    var isStopping: Bool = false
    var isPreparing: Bool = false
    var errorMessage: String? = nil
    
    // Selected Locale
    var selectedLocale: Locale = Locale.current {
        didSet {
            selectedLocaleIdentifier = selectedLocale.identifier
        }
    }
    var selectedLocaleIdentifier: String = Locale.current.identifier
    
    var selectedLocaleDisplayName: String {
        Locale.current.localizedString(forIdentifier: selectedLocaleIdentifier)
            ?? selectedLocaleIdentifier
    }
    
    var supportedLocales: [LocaleItem] = SpeechLocaleHelper.defaultLocaleItems
    
    var fullTranscript: String {
        transcriber.fullTranscript
    }
    
    var partialText: String {
        transcriber.volatileText
    }
    
    var finalizedText: String {
        transcriber.finalizedText
    }
    
    var tokens: [SpeechTranscriptionToken] {
        transcriber.tokens
    }
    
    var engineDescription: String {
        transcriber.engineDescription
    }
    
    var isDownloadingModel: Bool {
        transcriber.isDownloadingModel
    }
    
    var downloadProgress: Progress? {
        transcriber.downloadProgress
    }
    
    /// Dependency-injected initializer: can inject any service conforming to SpeechTranscriptionService
    init(
        transcriber: (any SpeechTranscriptionService)? = nil,
        engineMode: SpeechEngineMode? = nil,
        recorder: NativeSpeechRecorder? = nil
    ) {
        self.recorder = recorder ?? NativeSpeechRecorder()
        let initialMode = engineMode ?? (SpeechLocaleHelper.isModernSupported ? .modern : .legacy)
        self.selectedEngineMode = initialMode
        self.transcriber = transcriber ?? SpeechTranscriptionServiceFactory.makeService(forceLegacy: initialMode == .legacy)
        Task {
            await loadSupportedLocales()
        }
    }
    
    /// Switch between Modern (SpeechAnalyzer) and Legacy (SFSpeechRecognizer) engines on the fly
    func switchEngine(to mode: SpeechEngineMode) {
        guard mode != selectedEngineMode else { return }
        
        if mode == .modern && !isModernEngineSupported {
            errorMessage = "Modern SpeechAnalyzer engine requires iOS 26 or later."
            return
        }
        
        let wasRecording = isRecording
        if wasRecording {
            stop()
        }
        
        self.selectedEngineMode = mode
        let forceLegacy = (mode == .legacy)
        self.transcriber = SpeechTranscriptionServiceFactory.makeService(forceLegacy: forceLegacy)
        
        Task {
            await loadSupportedLocales()
            if wasRecording {
                try? await Task.sleep(nanoseconds: 300_000_000)
                start()
            }
        }
    }
    
    /// Dynamically loads supported locales for the active engine
    func loadSupportedLocales() async {
        self.supportedLocales = await SpeechLocaleHelper.loadSupportedLocales(for: selectedEngineMode)
    }
    
    func start() {
        guard !isRecording, !isStopping, !isPreparing else { return }
        errorMessage = nil
        isPreparing = true
        
        streamingTask = Task {
            do {
                try await transcriber.setUpTranscriber(locale: selectedLocale)
                isPreparing = false
                isRecording = true
                
                let stream = try await recorder.startStreaming()
                for await buffer in stream {
                    guard !Task.isCancelled else { break }
                    try transcriber.streamAudioBuffer(buffer)
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    SpeechLog.viewModel.error("Transcription error: \(error.localizedDescription)")
                }
            }
            self.isRecording = false
            self.isPreparing = false
        }
    }
    
    func stop() {
        guard isRecording, !isStopping else { return }
        isStopping = true
        
        streamingTask?.cancel()
        streamingTask = nil
        
        Task {
            recorder.stop()
            try? await transcriber.finishTranscribing()
            self.isRecording = false
            self.isStopping = false
        }
    }
    
    func clearTranscript() {
        transcriber.clear()
        errorMessage = nil
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    func updateLocaleAndRestart(identifier: String) {
        selectedLocale = Locale(identifier: identifier)
        let wasRecording = isRecording
        
        if wasRecording {
            stop()
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                start()
            }
        }
    }
}
