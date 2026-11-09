//
//  NativeSpeechTranscriber.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import AVFoundation
import Foundation
import Speech
import SwiftUI

enum NativeTranscriptionError: LocalizedError {
    case couldNotDownloadModel
    case failedToSetupRecognitionStream
    case invalidAudioDataType
    case localeNotSupported
    case recognitionFailed(String)
    
    var errorDescription: String? {
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

@Observable
@MainActor
final class NativeSpeechTranscriber {
    
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<Void, Never>?
    
    private let converter = NativeBufferConverter()
    private var analyzerFormat: AVAudioFormat?
    
    // Published states for UI
    var finalizedText: String = ""
    var volatileText: String = ""
    var downloadProgress: Progress?
    var isDownloadingModel: Bool = false
    
    var fullTranscript: String {
        let first = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        return first + " " + second
    }
    
    func setUpTranscriber(locale: Locale) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber
        
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        
        try await ensureModel(transcriber: transcriber, locale: locale)
        
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = stream
        self.inputBuilder = builder
        
        recognizerTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { break }
                    let text = String(result.text.characters)
                    
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
                WhisperLog.live.error("Native speech recognition stream ended: \(error.localizedDescription)")
            }
        }
        
        try await analyzer.start(inputSequence: stream)
    }
    
    func streamAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let inputBuilder, let analyzerFormat else {
            throw NativeTranscriptionError.invalidAudioDataType
        }
        
        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }
    
    func finishTranscribing() async throws {
        inputBuilder?.finish()
        inputBuilder = nil
        inputSequence = nil
        
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        converter.reset()
    }
    
    func clear() {
        finalizedText = ""
        volatileText = ""
    }
    
    // MARK: - Model Availability & Download
    
    func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw NativeTranscriptionError.localeNotSupported
        }
        
        if await installed(locale: locale) {
            return
        }
        
        try await downloadIfNeeded(for: transcriber)
    }
    
    func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }
    
    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }
    
    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        isDownloadingModel = true
        defer { isDownloadingModel = false }
        
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            self.downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
        }
    }
}

