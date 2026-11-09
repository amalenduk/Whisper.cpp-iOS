//
//  WhisperContext.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation
import whisper

actor WhisperContext {
    
    // MARK: - Properties
    
    private let context: OpaquePointer
    
    private let sampleRate: Double = 16_000
    
    // MARK: - Initialization
    
    private init(context: OpaquePointer) {
        self.context = context
    }
    
    deinit {
        whisper_free(context)
    }
    
    // MARK: - Context Creation
    
    static func createContext() throws -> WhisperContext {
        // Preferred candidate models in order of quality/performance:
        let candidates = [
            "ggml-large-v3-turbo-q5_0",
            "ggml-large-v3-turbo",
            "ggml-small-q5_1",
            "ggml-small",
            "ggml-base-q5_1",
            "ggml-base",
            "ggml-tiny"
        ]
        
        var resolvedURL: URL?
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "bin", subdirectory: "models")
                ?? Bundle.main.url(forResource: name, withExtension: "bin") {
                resolvedURL = url
                break
            }
        }
        
        guard let modelURL = resolvedURL else {
            WhisperLog.inference.fault("No Whisper model found in app bundle matching candidates: \(candidates.joined(separator: ", "))")
            throw WhisperError.couldNotInitializeContext
        }
        
        var params = whisper_context_default_params()
        
        #if targetEnvironment(simulator)
        params.use_gpu = false
        #else
        params.flash_attn = true
        #endif
        
        guard let context = whisper_init_from_file_with_params(
            modelURL.path,
            params
        ) else {
            WhisperLog.inference.fault("Failed to initialize Whisper context from model: \(modelURL.path)")
            throw WhisperError.couldNotInitializeContext
        }
        
        WhisperLog.inference.info("Whisper context initialized successfully with model: \(modelURL.lastPathComponent)")
        return WhisperContext(context: context)
    }
    
    // MARK: - Transcription
    
    func transcribe(
        samples: [Float],
        configuration: WhisperConfiguration = WhisperConfiguration()
    ) throws -> WhisperTranscription {
        
        // Validate input.
        
        guard !samples.isEmpty else {
            throw WhisperError.emptyAudio
        }
        
        guard samples.count <= Int(Int32.max) else {
            throw WhisperError.audioTooLong
        }
        
        guard samples.allSatisfy({ $0.isFinite }) else {
            throw WhisperError.audioContainsInvalidSamples
        }
        
        let threadCount = Int32(
            configuration.resolvedThreadCount
        )
        
        // Configure Whisper.
        
        let execute: (
            UnsafePointer<CChar>?
        ) throws -> WhisperTranscription = { [self] languagePointer in
            
            var params = whisper_full_default_params(
                WHISPER_SAMPLING_GREEDY
            )
            
            params.print_realtime = false
            params.print_progress = false
            params.print_timestamps = false
            params.print_special = false
            
            params.translate = configuration.translateToEnglish
            params.language = languagePointer
            
            params.n_threads = threadCount
            params.offset_ms = 0
            
            params.no_context = configuration.noContext
            params.single_segment = configuration.singleSegment
            
            // Standard decoding parameters:
            params.no_timestamps = true
            params.suppress_blank = configuration.suppressBlank
            params.suppress_nst = configuration.suppressNonSpeechTokens
            params.temperature = configuration.temperature
            params.temperature_inc = 0.0
            
            // Noise & Hallucination filters:
            params.no_speech_thold = configuration.noSpeechThreshold
            params.logprob_thold = configuration.logprobThreshold
            
            // Run inference.
            
            whisper_reset_timings(context)
            
            let result = samples.withUnsafeBufferPointer { buffer in
                // whisper.cpp requires 16kHz audio. Ensure we feed valid samples.
                whisper_full(
                    context,
                    params,
                    buffer.baseAddress,
                    Int32(buffer.count)
                )
            }
            
            WhisperLog.inference.info("whisper_full code: \(result), samples: \(samples.count) (\(String(format: "%.2f", Double(samples.count) / 16000.0))s audio), lang: \(configuration.language ?? "auto")")
            
            guard result == 0 else {
                WhisperLog.inference.error("whisper_full failed with error code: \(result)")
                throw WhisperError.transcriptionFailed(result)
            }
            
            // Extract transcription segments.
            
            let segmentCount = Int(
                whisper_full_n_segments(context)
            )
            
            var segments: [WhisperSegment] = []
            segments.reserveCapacity(segmentCount)
            
            var completeText = ""
            
            for index in 0..<segmentCount {
                
                guard let textPointer = whisper_full_get_segment_text(
                    context,
                    Int32(index)
                ) else {
                    throw WhisperError.invalidSegmentText
                }
                
                let segmentText = String(cString: textPointer)
                
                // Whisper timestamps use centiseconds.
                
                let startTime = TimeInterval(
                    whisper_full_get_segment_t0(
                        context,
                        Int32(index)
                    )
                ) / 100.0
                
                let endTime = TimeInterval(
                    whisper_full_get_segment_t1(
                        context,
                        Int32(index)
                    )
                ) / 100.0
                
                let segment = WhisperSegment(
                    id: index,
                    text: segmentText,
                    startTime: startTime,
                    endTime: endTime
                )
                
                segments.append(segment)
                completeText += segmentText
            }
            
            // Detect the language used by Whisper for this transcription.
            let languageID = whisper_full_lang_id(context)

            let detectedLanguage: String? = {
                guard languageID >= 0,
                      let languagePointer = whisper_lang_str(languageID) else {
                    return nil
                }

                return String(cString: languagePointer)
            }()
            
            return WhisperTranscription(
                text: completeText,
                segments: segments,
                duration: Double(samples.count) / sampleRate,
                detectedLanguage: detectedLanguage
            )
        }
        
        // Keep the language pointer alive throughout inference.
        
        if let language = configuration.language {
            return try language.withCString {
                try execute($0)
            }
        }
        
        return try execute(nil)
    }
}
