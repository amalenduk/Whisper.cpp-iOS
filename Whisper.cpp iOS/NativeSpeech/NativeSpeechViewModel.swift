//
//  NativeSpeechViewModel.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation
import Speech
import SwiftUI

@Observable
@MainActor
final class NativeSpeechViewModel {
    
    private let recorder = NativeSpeechRecorder()
    let transcriber = NativeSpeechTranscriber()
    
    private var streamingTask: Task<Void, Never>?
    
    // UI State Properties
    var isRecording: Bool = false
    var isStopping: Bool = false
    var isPreparing: Bool = false
    var errorMessage: String? = nil
    
    // Selected Locale
    var selectedLocale: Locale = Locale.current {
        didSet {
            selectedLocaleIdentifier = selectedLocale.identifier(.bcp47)
        }
    }
    var selectedLocaleIdentifier: String = Locale.current.identifier(.bcp47)
    
    var selectedLocaleDisplayName: String {
        Locale.current.localizedString(forIdentifier: selectedLocaleIdentifier)
            ?? selectedLocaleIdentifier
    }
    
    nonisolated struct LocaleItem: Identifiable, Hashable, Sendable {
        let identifier: String
        let name: String
        let isInstalled: Bool
        
        var id: String { identifier }
    }
    
    /// Default standard locales shown immediately while dynamic locales are fetched from SpeechTranscriber
    private static let defaultLocales: [LocaleItem] = [
        LocaleItem(identifier: "en-US", name: "English (US)", isInstalled: true),
        LocaleItem(identifier: "es-ES", name: "Spanish (Spain)", isInstalled: false),
        LocaleItem(identifier: "fr-FR", name: "French (France)", isInstalled: false),
        LocaleItem(identifier: "de-DE", name: "German (Germany)", isInstalled: false),
        LocaleItem(identifier: "it-IT", name: "Italian (Italy)", isInstalled: false),
        LocaleItem(identifier: "hi-IN", name: "Hindi (India)", isInstalled: false),
        LocaleItem(identifier: "zh-CN", name: "Chinese (Mandarin)", isInstalled: false),
        LocaleItem(identifier: "ja-JP", name: "Japanese (Japan)", isInstalled: false)
    ]
    
    var supportedLocales: [LocaleItem] = defaultLocales
    
    var fullTranscript: String {
        transcriber.fullTranscript
    }
    
    var partialText: String {
        transcriber.volatileText
    }
    
    var finalizedText: String {
        transcriber.finalizedText
    }
    
    init() {
        Task {
            await loadSupportedLocales()
        }
    }
    
    /// Dynamically loads all supported and installed locales directly from Apple SpeechTranscriber.
    func loadSupportedLocales() async {
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        let current = Locale.current
        
        if !supported.isEmpty {
            var items = supported.map { loc in
                let bcp47 = loc.identifier(.bcp47)
                let name = current.localizedString(forIdentifier: bcp47)
                    ?? loc.localizedString(forIdentifier: bcp47)
                    ?? bcp47
                let isInstalled = installed.contains(bcp47)
                return LocaleItem(identifier: bcp47, name: name, isInstalled: isInstalled)
            }
            
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.supportedLocales = items
        } else {
            self.supportedLocales = Self.defaultLocales.map { item in
                LocaleItem(identifier: item.identifier, name: item.name, isInstalled: installed.contains(item.identifier))
            }
        }
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

