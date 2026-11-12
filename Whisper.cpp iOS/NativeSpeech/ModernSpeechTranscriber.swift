//
//  ModernSpeechTranscriber.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 12/11/26.
//

import AVFoundation
import Foundation
import Speech

@available(iOS 26.0, macOS 26.0, *)
public enum ModernTranscriptionError: LocalizedError {
    case couldNotDownloadModel
    case failedToSetupRecognitionStream
    case invalidAudioDataType
    case localeNotSupported
    case recognitionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .couldNotDownloadModel:
            return "Could not download the speech model for the selected language."
        case .failedToSetupRecognitionStream:
            return "Could not set up the speech recognition stream."
        case .invalidAudioDataType:
            return "Unsupported audio format for SpeechAnalyzer."
        case .localeNotSupported:
            return "This language/locale is not supported on-device by SpeechAnalyzer."
        case .recognitionFailed(let reason):
            return "Speech recognition failed: \(reason)"
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Observable
@MainActor
public final class ModernSpeechTranscriber: SpeechTranscriptionService {
    
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<Void, Never>?
    
    private let converter = NativeBufferConverter()
    private var analyzerFormat: AVAudioFormat?
    
    // Published states for UI
    public var finalizedText: String = ""
    public var volatileText: String = ""
    public var tokens: [SpeechTranscriptionToken] = []
    public var downloadProgress: Progress? = nil
    public var isDownloadingModel: Bool = false
    
    public var engineDescription: String {
        "Apple SpeechAnalyzer (iOS 26+)"
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
        // Resolve matching locale among supported
        let supported = await SpeechTranscriber.supportedLocales
        let supportedIDs = supported.map { $0.identifier(.bcp47) }
        let resolvedID = SpeechLocaleHelper.findBestMatchingLocale(
            for: locale.identifier(.bcp47),
            in: supportedIDs
        )
        let targetLocale = Locale(identifier: resolvedID)
        
        let transcriber = SpeechTranscriber(
            locale: targetLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber
        
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        
        try await ensureModel(transcriber: transcriber, locale: targetLocale)
        
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = stream
        self.inputBuilder = builder
        
        recognizerTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { break }
                    let text = String(result.text.characters)
                    
                    // Extract tokens from words
                    let words = text.split(separator: " ").map { String($0) }
                    self.tokens = words.map { SpeechTranscriptionToken(text: $0) }
                    
                    if result.isFinal {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            if self.finalizedText.isEmpty {
                                self.finalizedText = trimmed
                            } else {
                                self.finalizedText += " " + trimmed
                            }
                        }
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }
                }
            } catch {
                SpeechLog.modern.error("SpeechAnalyzer recognition stream error: \(error.localizedDescription)")
            }
        }
        
        try await analyzer.start(inputSequence: stream)
    }
    
    public func streamAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let inputBuilder, let analyzerFormat else {
            throw ModernTranscriptionError.invalidAudioDataType
        }
        
        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }
    
    public func finishTranscribing() async throws {
        inputBuilder?.finish()
        inputBuilder = nil
        inputSequence = nil
        
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        converter.reset()
    }
    
    public func clear() {
        finalizedText = ""
        volatileText = ""
        tokens = []
    }
    
    // MARK: - Model Availability & Download
    
    private func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw ModernTranscriptionError.localeNotSupported
        }
        
        if await installed(locale: locale) {
            return
        }
        
        try await downloadIfNeeded(for: transcriber)
    }
    
    private func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }
    
    private func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }
    
    private func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        isDownloadingModel = true
        defer { isDownloadingModel = false }
        
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            self.downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
        }
    }
}

