//
//  WhisperAudioRingBuffer.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import Foundation

/// A lock-free, zero-allocation ring buffer for real-time audio threads.
/// Producer writes from the audio tap (without malloc/heap allocations).
/// Consumer reads on a background dispatch/async worker.
nonisolated final class WhisperAudioRingBuffer: @unchecked Sendable {
    
    private(set) var capacity: Int
    private let buffer: UnsafeMutablePointer<Float>
    private var writeHead: Int = 0
    private var readHead: Int = 0
    private(set) var overflowCount: Int = 0
    private let lock = NSLock()
    
    init(capacity: Int = 48_000 * 3) { // 3 seconds at 48kHz (144,000 Float32 samples ~ 576 KB)
        self.capacity = capacity
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.buffer.initialize(repeating: 0, count: capacity)
    }
    
    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }
    
    /// Real-time safe write method. No allocations.
    /// Can downmix multi-channel into mono directly into the preallocated buffer.
    func write(channelData: UnsafePointer<UnsafeMutablePointer<Float>>, frameCount: Int, channelCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        let channelScale = 1.0 / Float(channelCount)
        
        for frame in 0..<frameCount {
            var sample: Float = 0
            for channel in 0..<channelCount {
                sample += channelData[channel][frame] * channelScale
            }
            
            buffer[writeHead] = sample
            writeHead = (writeHead + 1) % capacity
            
            // Overwrite protection: advance readHead if buffer is full
            if writeHead == readHead {
                readHead = (readHead + 1) % capacity
                overflowCount += 1
            }
        }
    }
    
    /// Reads available mono samples out to the consumer thread.
    func readAvailable() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        
        let availableCount: Int
        if writeHead >= readHead {
            availableCount = writeHead - readHead
        } else {
            availableCount = (capacity - readHead) + writeHead
        }
        
        guard availableCount > 0 else { return [] }
        
        var result = [Float](repeating: 0, count: availableCount)
        for i in 0..<availableCount {
            result[i] = buffer[(readHead + i) % capacity]
        }
        readHead = (readHead + availableCount) % capacity
        
        return result
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        readHead = 0
        writeHead = 0
        overflowCount = 0
    }
}

