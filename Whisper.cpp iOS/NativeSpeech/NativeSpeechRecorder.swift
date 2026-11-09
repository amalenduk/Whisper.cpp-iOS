//
//  NativeSpeechRecorder.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import AVFoundation
import Foundation

@MainActor
final class NativeSpeechRecorder {
    
    enum RecorderError: LocalizedError {
        case microphonePermissionDenied
        case engineStartFailed(String)
        case invalidAudioFormat
        
        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access was denied. Please enable it in Settings."
            case .engineStartFailed(let reason):
                return "Audio engine failed to start: \(reason)"
            case .invalidAudioFormat:
                return "Microphone input format is invalid."
            }
        }
    }
    
    private let audioEngine = AVAudioEngine()
    private var outputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var isRecording = false
    
    func startStreaming() async throws -> AsyncStream<AVAudioPCMBuffer> {
        guard await requestMicrophonePermission() else {
            throw RecorderError.microphonePermissionDenied
        }
        
        try configureAudioSession()
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.invalidAudioFormat
        }
        
        inputNode.removeTap(onBus: 0)
        
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.outputContinuation = continuation
        
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.outputContinuation?.yield(buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            return stream
        } catch {
            inputNode.removeTap(onBus: 0)
            continuation.finish()
            outputContinuation = nil
            isRecording = false
            throw RecorderError.engineStartFailed(error.localizedDescription)
        }
    }
    
    func stop() {
        guard isRecording || outputContinuation != nil else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        outputContinuation?.finish()
        outputContinuation = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

