//
//  WhisperAudioConverter.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import AVFoundation
import Foundation

actor WhisperAudioConverter {

    // MARK: - Constants

    private let outputSampleRate: Double = 16_000

    // MARK: - Properties

    private var inputSampleRate: Double?

    private var converter: AVAudioConverter?

    private let outputFormat: AVAudioFormat
    
    private var inputFormat: AVAudioFormat?

    // MARK: - Initialization

    init() throws {

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw WhisperConverterError.couldNotCreateOutputFormat
        }

        outputFormat = format
    }

    // MARK: - Conversion

    /// Converts a captured audio chunk into mono 16 kHz Float32 samples.
    ///
    /// The converter is reused while the input sample rate remains unchanged.
    func convert(
        _ chunk: WhisperAudioChunk
    ) throws -> [Float] {

        guard !chunk.samples.isEmpty else {
            return []
        }

        guard chunk.sampleRate.isFinite,
              chunk.sampleRate > 0 else {
            throw WhisperConverterError.invalidSampleRate
        }

        guard chunk.samples.allSatisfy(\.isFinite) else {
            throw WhisperConverterError.invalidAudioSamples
        }

        try prepareConverter(
            inputSampleRate: chunk.sampleRate
        )

        guard let converter,
              let inputFormat = converter.inputFormat as AVAudioFormat? else {
            throw WhisperConverterError.converterUnavailable
        }

        let inputFrameCount = AVAudioFrameCount(chunk.samples.count)

        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: inputFrameCount
        ) else {
            throw WhisperConverterError.couldNotCreateInputBuffer
        }

        inputBuffer.frameLength = inputFrameCount

        guard let inputChannelData = inputBuffer.floatChannelData else {
            throw WhisperConverterError.invalidInputBuffer
        }

        chunk.samples.withUnsafeBufferPointer { source in

            guard let sourceAddress = source.baseAddress else {
                return
            }

            inputChannelData[0].update(
                from: sourceAddress,
                count: source.count
            )
        }

        let ratio = outputSampleRate / chunk.sampleRate

        let estimatedOutputFrames = Int(
            ceil(Double(inputFrameCount) * ratio)
        ) + 512

        guard estimatedOutputFrames <= Int(AVAudioFrameCount.max) else {
            throw WhisperConverterError.audioTooLong
        }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(estimatedOutputFrames)
        ) else {
            throw WhisperConverterError.couldNotCreateOutputBuffer
        }

        var suppliedInput = false
        var conversionError: NSError?

        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in

            guard !suppliedInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }

            suppliedInput = true
            inputStatus.pointee = .haveData

            return inputBuffer
        }

        if let conversionError {
            WhisperLog.converter.error("Audio conversion error: \(conversionError.localizedDescription)")
            throw WhisperConverterError.conversionFailed(
                conversionError.localizedDescription
            )
        }

        guard status != .error else {
            WhisperLog.converter.error("AVAudioConverter returned an error status.")
            throw WhisperConverterError.conversionFailed(
                "AVAudioConverter returned an error."
            )
        }

        guard let outputChannelData = outputBuffer.floatChannelData else {
            throw WhisperConverterError.invalidOutputBuffer
        }

        let outputFrameCount = Int(outputBuffer.frameLength)

        guard outputFrameCount > 0 else {
            return []
        }

        let outputSamples = Array(
            UnsafeBufferPointer(
                start: outputChannelData[0],
                count: outputFrameCount
            )
        )

        return outputSamples
    }

    // MARK: - Converter Configuration

    private func prepareConverter(
        inputSampleRate: Double
    ) throws {

        if self.inputSampleRate == inputSampleRate,
           converter != nil {
            return
        }

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw WhisperConverterError.couldNotCreateInputFormat
        }
        
        self.inputFormat = inputFormat

        guard let converter = AVAudioConverter(
            from: inputFormat,
            to: outputFormat
        ) else {
            throw WhisperConverterError.couldNotCreateConverter
        }

        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue

        self.converter = converter
        self.inputSampleRate = inputSampleRate
        WhisperLog.converter.info("Configured audio converter: \(Int(inputSampleRate))Hz -> 16000Hz (mono Float32).")
    }

    /// Resets converter state, for example after an audio route change.
    func reset() {
        WhisperLog.converter.info("Audio converter reset.")
        converter?.reset()
        converter = nil
        inputFormat = nil
        inputSampleRate = nil
    }
}
