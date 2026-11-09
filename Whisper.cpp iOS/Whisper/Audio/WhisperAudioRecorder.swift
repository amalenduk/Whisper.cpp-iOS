//
//  WhisperAudioRecorder.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import AVFoundation
import Foundation

@MainActor
final class WhisperAudioRecorder {
    
    // MARK: - Properties
    
    private let audioEngine = AVAudioEngine()
    
    private var continuation:
    AsyncThrowingStream<WhisperAudioChunk, Error>.Continuation?
    
    private var isRunning = false
    
    private let preferredBufferDuration: TimeInterval = 0.1
    
    private let ringBuffer = WhisperAudioRingBuffer()
    private var consumerTask: Task<Void, Never>?
    
    private var observerTasks: [Task<Void, Never>] = []
    
    // MARK: - Initialization
    
    init() {}
    
    deinit {
        for task in observerTasks {
            task.cancel()
        }
    }
    
    // MARK: - Recording
    
    /// Requests microphone access, configures the audio session,
    /// and starts continuous microphone capture.
    ///
    /// - Returns: An asynchronous stream of captured audio chunks.
    func start() async throws
    -> AsyncThrowingStream<WhisperAudioChunk, Error> {
        
        guard !isRunning else {
            throw WhisperRecorderError.alreadyRecording
        }
        
        try await requestMicrophonePermission()
        try configureAudioSession()
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0 else {
            throw WhisperRecorderError.invalidAudioFormat
        }
        
        // This implementation expects Float32 microphone input.
        // AVAudioEngine's normal iOS microphone input format is Float32.
        guard inputFormat.commonFormat == .pcmFormatFloat32,
              inputFormat.isInterleaved == false else {
            throw WhisperRecorderError.unsupportedAudioFormat
        }
        
        let stream = AsyncThrowingStream<WhisperAudioChunk, Error> {
            continuation in
            
            self.continuation = continuation
            
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stop()
                }
            }
        }
        
        let sampleRate = inputFormat.sampleRate
        let channelCount = Int(inputFormat.channelCount)
        
        WhisperLog.audio.info("Starting audio recording with format: \(Int(sampleRate))Hz, \(channelCount) ch, Float32=\(inputFormat.commonFormat == .pcmFormatFloat32)")
        
        let ringBuffer = self.ringBuffer
        ringBuffer.reset()
        
        // Real-time audio tap: ONLY write directly to preallocated ring buffer.
        // ZERO heap memory allocations occur on the audio IO thread.
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4_800,
            format: inputFormat
        ) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            
            ringBuffer.write(
                channelData: channelData,
                frameCount: frameCount,
                channelCount: channelCount
            )
        }
        
        // Dedicated background consumer reading from ring buffer at regular cadence
        let streamContinuation = self.continuation
        consumerTask = Task.detached(priority: .userInitiated) { [weak self] in
            WhisperLog.audio.info("Audio consumer task started.")
            var emptyCount = 0
            var lastReportedOverflow = 0
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms cadence
                guard self != nil else { break }
                
                // Monitor ring buffer overflows
                let currentOverflow = ringBuffer.overflowCount
                if currentOverflow > lastReportedOverflow {
                    WhisperLog.audio.warning("Ring buffer overflow: \(currentOverflow - lastReportedOverflow) frames overwritten! Total overflows: \(currentOverflow). Consumer is lagging.")
                    lastReportedOverflow = currentOverflow
                }
                
                let samples = ringBuffer.readAvailable()
                guard !samples.isEmpty else {
                    emptyCount += 1
                    if emptyCount % 30 == 0 { // Every ~3 seconds of continuous empty reads
                        WhisperLog.audio.warning("No audio samples from ring buffer for \(emptyCount / 10)s. Check if microphone hardware or AVAudioEngine stalled.")
                    }
                    continue
                }
                
                if emptyCount >= 30 {
                    WhisperLog.audio.info("Audio consumer resumed receiving samples after \(emptyCount / 10)s stall.")
                }
                emptyCount = 0
                
                let chunk = WhisperAudioChunk(
                    samples: samples,
                    sampleRate: sampleRate,
                    timestamp: ProcessInfo.processInfo.systemUptime
                )
                streamContinuation?.yield(chunk)
            }
            WhisperLog.audio.info("Audio consumer task ended.")
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            isRunning = true
            setupAudioSessionObservers()
            WhisperLog.audio.info("Audio engine running successfully.")
            
            return stream
            
        } catch {
            WhisperLog.audio.error("Audio engine failed to start: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            continuation?.finish()
            continuation = nil
            
            try? deactivateAudioSession()
            
            throw WhisperRecorderError.recordingFailed(
                error.localizedDescription
            )
        }
    }
    
    /// Stops microphone capture and finishes the audio stream.
    func stop() {
        WhisperLog.audio.info("Stopping audio recording...")
        removeAudioSessionObservers()
        
        consumerTask?.cancel()
        consumerTask = nil
        
        guard isRunning || continuation != nil else {
            return
        }
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        audioEngine.inputNode.removeTap(onBus: 0)
        
        continuation?.finish()
        continuation = nil
        
        isRunning = false
        
        try? deactivateAudioSession()
    }
    
    // MARK: - Microphone Permission
    
    private func requestMicrophonePermission() async throws {
        if #available(iOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                throw WhisperRecorderError.microphonePermissionDenied
            }
        } else {
            let audioSession = AVAudioSession.sharedInstance()
            let granted = await withCheckedContinuation { continuation in
                audioSession.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else {
                throw WhisperRecorderError.microphonePermissionDenied
            }
        }
    }
    
    // MARK: - Audio Session
    
    private func configureAudioSession() throws {
        
        let audioSession = AVAudioSession.sharedInstance()
        
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [
                .defaultToSpeaker,
                .allowBluetoothHFP
            ]
        )
        
        // These are preferences, not guarantees.
        try audioSession.setPreferredSampleRate(16_000)
        
        try audioSession.setPreferredIOBufferDuration(
            preferredBufferDuration
        )
        
        try audioSession.setActive(true)
    }
    
    private func deactivateAudioSession() throws {
        
        try AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
    
    // MARK: - Interruption & Route Change Observers
    
    private func setupAudioSessionObservers() {
        removeAudioSessionObservers()
        
        // 1. Audio Session Interruption (Phone call, alarm, Siri, etc.)
        let interruptionTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                guard let self, self.isRunning else { return }
                
                guard let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                    continue
                }
                
                switch type {
                case .began:
                    self.handleInterruptionBegan()
                case .ended:
                    let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    self.handleInterruptionEnded(shouldResume: options.contains(.shouldResume))
                @unknown default:
                    break
                }
            }
        }
        
        // 2. Audio Route Change (Bluetooth connect/disconnect, headphones unplugged)
        let routeChangeTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                guard let self, self.isRunning else { return }
                
                guard let userInfo = notification.userInfo,
                      let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                    continue
                }
                
                self.handleRouteChange(reason: reason)
            }
        }
        
        // 3. Media Services Reset (Media server daemon restarted)
        let resetTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.mediaServicesWereResetNotification) {
                guard let self, self.isRunning else { return }
                self.handleMediaServicesReset()
            }
        }
        
        observerTasks = [interruptionTask, routeChangeTask, resetTask]
    }
    
    private func removeAudioSessionObservers() {
        for task in observerTasks {
            task.cancel()
        }
        observerTasks.removeAll()
    }
    
    private func handleInterruptionBegan() {
        WhisperLog.audio.warning("Audio session interruption BEGAN. Pausing audio engine.")
        guard isRunning else { return }
        if audioEngine.isRunning {
            audioEngine.pause()
        }
    }
    
    private func handleInterruptionEnded(shouldResume: Bool) {
        WhisperLog.audio.info("Audio session interruption ENDED. shouldResume: \(shouldResume)")
        guard isRunning else { return }
        if shouldResume {
            do {
                try configureAudioSession()
                try audioEngine.start()
                WhisperLog.audio.info("Audio engine successfully resumed after interruption.")
            } catch {
                WhisperLog.audio.error("Failed to resume after interruption: \(error.localizedDescription)")
                continuation?.finish(throwing: WhisperRecorderError.recordingFailed("Failed to resume after interruption: \(error.localizedDescription)"))
                stop()
            }
        } else {
            WhisperLog.audio.warning("Audio session was interrupted and system indicated not to resume.")
            continuation?.finish(throwing: WhisperRecorderError.interrupted)
            stop()
        }
    }
    
    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        WhisperLog.audio.warning("Audio route change: reason=\(reason.rawValue)")
        guard isRunning else { return }
        
        switch reason {
        case .oldDeviceUnavailable:
            // e.g. Bluetooth headset or wired headphones disconnected
            WhisperLog.audio.warning("Route change: Old audio device unavailable (headset/Bluetooth disconnected). Stopping.")
            continuation?.finish(throwing: WhisperRecorderError.interrupted)
            stop()
        case .newDeviceAvailable, .categoryChange, .override:
            // Route format might have changed (e.g. 44.1kHz -> 16kHz for Bluetooth)
            let inputNode = audioEngine.inputNode
            let newFormat = inputNode.inputFormat(forBus: 0)
            WhisperLog.audio.info("Route change: New format is \(Int(newFormat.sampleRate))Hz, \(newFormat.channelCount) ch.")
            if newFormat.sampleRate <= 0 || newFormat.channelCount <= 0 {
                WhisperLog.audio.error("Invalid microphone format after route change.")
                continuation?.finish(throwing: WhisperRecorderError.invalidAudioFormat)
                stop()
            }
        default:
            break
        }
    }
    
    private func handleMediaServicesReset() {
        WhisperLog.audio.fault("Media services were reset by iOS. Full engine reset required.")
        continuation?.finish(throwing: WhisperRecorderError.recordingFailed("Media services were reset by system."))
        stop()
    }
}
