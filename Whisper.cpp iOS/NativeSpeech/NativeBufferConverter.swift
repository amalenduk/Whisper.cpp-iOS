//
//  NativeBufferConverter.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import AVFoundation
import Foundation

final class NativeBufferConverter: @unchecked Sendable {
    
    enum ConverterError: LocalizedError {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .failedToCreateConverter:
                return "Failed to initialize AVAudioConverter."
            case .failedToCreateConversionBuffer:
                return "Failed to create destination conversion buffer."
            case .conversionFailed(let reason):
                return "Audio buffer conversion failed: \(reason)"
            }
        }
    }
    
    private var converter: AVAudioConverter?
    
    func convertBuffer(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != targetFormat else {
            return buffer
        }
        
        if converter == nil || converter?.outputFormat != targetFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            converter?.primeMethod = .none
        }
        
        guard let converter else {
            throw ConverterError.failedToCreateConverter
        }
        
        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        
        guard let conversionBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity) else {
            throw ConverterError.failedToCreateConversionBuffer
        }
        
        var nsError: NSError?
        var bufferProcessed = false
        
        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
            defer { bufferProcessed = true }
            inputStatusPointer.pointee = bufferProcessed ? .noDataNow : .haveData
            return bufferProcessed ? nil : buffer
        }
        
        if let nsError {
            throw ConverterError.conversionFailed(nsError.localizedDescription)
        }
        
        guard status != .error else {
            throw ConverterError.conversionFailed("AVAudioConverter returned an error status.")
        }
        
        return conversionBuffer
    }
    
    func reset() {
        converter?.reset()
        converter = nil
    }
}

