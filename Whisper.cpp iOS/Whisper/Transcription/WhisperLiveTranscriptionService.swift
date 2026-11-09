//
//  WhisperLiveTranscriptionService.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

actor WhisperLiveTranscriptionService {

    // MARK: - Dependencies

    private let recorder: WhisperAudioRecorder
    private let converter: WhisperAudioConverter
    private let whisperContext: WhisperContext

    // MARK: - Configuration
    
    private var configuration: WhisperConfiguration

    private let targetSampleRate: Double = 16_000
    private let minimumPhraseDuration: TimeInterval = 0.25
    private let partialInterval: TimeInterval = 0.6
    private let minimumPartialDuration: TimeInterval = 0.5
    
    private var partialTask: Task<Void, Never>?
    private var isTranscribing = false

    // MARK: - Processing

    private var voiceActivityDetector = WhisperVoiceActivityDetector()

    private var audioBuffer = WhisperAudioBuffer(
        sampleRate: 16_000,
        maximumDuration: 30
    )

    private var committedText = ""
    private var lastPartialTime: TimeInterval = 0

    // MARK: - Lifecycle

    private var processingTask: Task<Void, Never>?

    private var resultContinuation:
        AsyncThrowingStream<WhisperLiveTranscriptionResult, Error>.Continuation?

    private var isRunning = false

    // MARK: - Initialization

    init(
        recorder: WhisperAudioRecorder,
        converter: WhisperAudioConverter,
        whisperContext: WhisperContext,
        configuration: WhisperConfiguration = .default
    ) {
        self.recorder = recorder
        self.converter = converter
        self.whisperContext = whisperContext
        self.configuration = configuration
        self.voiceActivityDetector = WhisperVoiceActivityDetector(
            speechThreshold: configuration.vadSpeechThreshold,
            silenceDuration: configuration.vadSilenceDuration
        )
    }

    // MARK: - Start

    /// Starts microphone capture and returns live transcription updates.
    func start() async throws
        -> AsyncThrowingStream<WhisperLiveTranscriptionResult, Error> {

        WhisperLog.live.info("Starting live transcription service (language: \(self.configuration.language ?? "auto")).")

        if isRunning {
            await stop()
        }

        let audioStream = try await recorder.start()

        let (resultStream, continuation) =
            AsyncThrowingStream<WhisperLiveTranscriptionResult, Error>.makeStream()

        resultContinuation = continuation
        isRunning = true

        resetProcessingState()

        continuation.onTermination = { @Sendable [weak self] _ in
            Task {
                await self?.stop()
            }
        }

        processingTask = Task { [weak self] in
            await self?.consume(audioStream)
        }

        return resultStream
    }

    // MARK: - Stop

    /// Stops microphone capture and waits for pending audio processing.
    func stop() async {
        WhisperLog.live.info("Stopping live transcription service...")

        guard isRunning || processingTask != nil else {
            return
        }

        // Finishing the recorder stream allows the consumer to drain
        // already captured chunks and finalize the current phrase.
        await recorder.stop()

        if let processingTask {
            await processingTask.value
        }

        processingTask = nil
        partialTask?.cancel()
        partialTask = nil
        isTranscribing = false
        isRunning = false

        resultContinuation?.finish()
        resultContinuation = nil

        await converter.reset()

        resetProcessingState()
    }

    // MARK: - Locale / Configuration Update

    /// Updates the spoken language / locale dynamically.
    /// Use nil to revert to auto language detection.
    func updateLanguage(_ language: String?) {
        configuration = WhisperConfiguration(
            language: language,
            translateToEnglish: configuration.translateToEnglish,
            threadCount: configuration.threadCount,
            noContext: configuration.noContext,
            singleSegment: configuration.singleSegment,
            temperature: configuration.temperature,
            noSpeechThreshold: configuration.noSpeechThreshold,
            logprobThreshold: configuration.logprobThreshold,
            suppressBlank: configuration.suppressBlank,
            suppressNonSpeechTokens: configuration.suppressNonSpeechTokens,
            vadSpeechThreshold: configuration.vadSpeechThreshold,
            vadSilenceDuration: configuration.vadSilenceDuration
        )
    }
    
    // MARK: - Clear Transcript
    
    /// Clears accumulated transcript and current audio buffer so new speech starts fresh.
    func clearTranscript() {
        partialTask?.cancel()
        partialTask = nil
        committedText = ""
        audioBuffer.reset()
        lastPartialTime = 0
        WhisperLog.live.info("Transcript and audio buffer cleared by user request.")
    }

    // MARK: - Audio Consumption

    private func consume(
        _ audioStream: AsyncThrowingStream<WhisperAudioChunk, Error>
    ) async {
        WhisperLog.live.info("Audio consumer stream started.")

        do {
            for try await chunk in audioStream {

                try Task.checkCancellation()

                let lag = ProcessInfo.processInfo.systemUptime - chunk.timestamp
                if lag > 1.5 {
                    WhisperLog.live.warning("Audio processing backlog! Lag: \(String(format: "%.2f", lag))s. Whisper inference may be slower than real-time.")
                }

                let samples = try await converter.convert(chunk)

                guard !samples.isEmpty else {
                    continue
                }

                try await processAudio(samples)
            }

            // Flush a remaining phrase when the recording stream ends.
            if !audioBuffer.isEmpty {
                WhisperLog.live.info("Audio stream ended, finalizing remaining audio buffer...")
                try await finalizeCurrentPhrase()
            }

            resultContinuation?.finish()
            WhisperLog.live.info("Audio stream finished normally.")

        } catch is CancellationError {
            WhisperLog.live.info("Audio consumption cancelled.")
            resultContinuation?.finish()

        } catch {
            WhisperLog.live.error("Audio consumption failed: \(error.localizedDescription)")
            resultContinuation?.finish(throwing: error)

            await recorder.stop()

            isRunning = false
            processingTask = nil
        }
    }

    // MARK: - Audio Processing

    private func processAudio(
        _ samples: [Float]
    ) async throws {

        let activity = voiceActivityDetector.process(
            samples: samples,
            sampleRate: targetSampleRate
        )

        // Include the silence that completes a phrase, but don't
        // continuously buffer silence when nobody is speaking.
        if activity.isSpeechActive || activity.didEndSpeech {

            let incomingDuration =
                Double(samples.count) / targetSampleRate

            // If the buffer approaches the 30-second limit, auto-finalize the phrase
            // and flush the buffer so continuous transcription never stops.
            if audioBuffer.duration + incomingDuration >= audioBuffer.maximumDuration {
                WhisperLog.live.warning("Audio buffer reached max 30s limit. Auto-finalizing phrase.")
                try await finalizeCurrentPhrase()
            } else {
                try audioBuffer.append(samples)
            }
        }

        guard activity.isSpeechActive else {

            if activity.didEndSpeech {
                try await finalizeCurrentPhrase()
            }

            return
        }

        guard audioBuffer.duration >= minimumPartialDuration else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime

        guard now - lastPartialTime >= partialInterval else {
            return
        }

        lastPartialTime = now

        guard !isTranscribing else {
            WhisperLog.live.debug("Skipping partial transcription: Whisper is currently busy.")
            return
        }

        partialTask?.cancel()
        partialTask = Task {
            try? await publishPartialTranscription()
        }
    }

    // MARK: - Partial Transcription

    private func publishPartialTranscription() async throws {

        guard !audioBuffer.isEmpty, !isTranscribing else {
            return
        }
        
        isTranscribing = true
        defer { isTranscribing = false }

        let samples = audioBuffer.snapshot()

        guard !Task.isCancelled else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        let transcription = try await whisperContext.transcribe(
            samples: samples,
            configuration: configuration
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        guard !Task.isCancelled else { return }

        let partialText = transcription.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !partialText.isEmpty else {
            return
        }

        WhisperLog.live.info("Partial transcription done in \(String(format: "%.2f", elapsed))s: '\(partialText)'")

        let result = WhisperLiveTranscriptionResult(
            transcript: combinedText(
                committedText,
                partialText
            ),
            partialText: partialText,
            finalizedText: "",
            detectedLanguage: transcription.detectedLanguage,
            isFinal: false,
            segments: transcription.segments
        )

        resultContinuation?.yield(result)
    }

    // MARK: - Final Transcription

    private func finalizeCurrentPhrase() async throws {

        partialTask?.cancel()
        partialTask = nil

        // Extract and reset the buffer synchronously.
        let audio = takeCurrentAudio()

        guard !audio.samples.isEmpty,
              audio.duration >= minimumPhraseDuration else {
            return
        }

        WhisperLog.live.info("Finalizing phrase of \(String(format: "%.2f", audio.duration))s (\(audio.samples.count) samples)...")
        let startTime = CFAbsoluteTimeGetCurrent()

        // No further access to audioBuffer in this async operation.
        let transcription = try await whisperContext.transcribe(
            samples: audio.samples,
            configuration: configuration
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        let finalText = transcription.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !finalText.isEmpty else {
            return
        }

        WhisperLog.live.info("Phrase finalized in \(String(format: "%.2f", elapsed))s: '\(finalText)'")

        committedText = combinedText(
            committedText,
            finalText
        )

        let result = WhisperLiveTranscriptionResult(
            transcript: committedText,
            partialText: "",
            finalizedText: finalText,
            detectedLanguage: transcription.detectedLanguage,
            isFinal: true,
            segments: transcription.segments
        )

        resultContinuation?.yield(result)
    }
    

    // MARK: - Helpers

    private func combinedText(
        _ first: String,
        _ second: String
    ) -> String {

        let first = first.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let second = second.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !first.isEmpty else {
            return second
        }

        guard !second.isEmpty else {
            return first
        }

        return first + " " + second
    }
    
    // MARK: - Audio Buffer Management

    private func takeCurrentAudio() -> (
        samples: [Float],
        duration: TimeInterval
    ) {
        let samples = audioBuffer.snapshot()
        let duration = audioBuffer.duration

        audioBuffer.reset()

        return (samples, duration)
    }

    private func resetProcessingState() {

        voiceActivityDetector.reset()
        audioBuffer.reset()

        committedText = ""
        lastPartialTime = 0
    }
}
