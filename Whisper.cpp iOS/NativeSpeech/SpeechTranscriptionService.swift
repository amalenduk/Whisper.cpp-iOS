//
//  SpeechTranscriptionService.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 12/11/26.
//

import AVFoundation
import Foundation

@MainActor
public protocol SpeechTranscriptionService: AnyObject {
    /// Full accumulated transcript text (finalized + volatile)
    var fullTranscript: String { get }
    
    /// Uncommitted/in-progress speech hypothesis for current utterance
    var volatileText: String { get }
    
    /// Committed final text
    var finalizedText: String { get }
    
    /// Tokens / word segments emitted by the speech recognizer
    var tokens: [SpeechTranscriptionToken] { get }
    
    /// Human-readable engine identifier
    var engineDescription: String { get }
    
    /// Whether an on-device model asset is currently downloading
    var isDownloadingModel: Bool { get }
    
    /// Progress of the model download if applicable
    var downloadProgress: Progress? { get }
    
    /// Set up recognizer session for given locale
    func setUpTranscriber(locale: Locale) async throws
    
    /// Stream live PCM audio buffer from recorder
    func streamAudioBuffer(_ buffer: AVAudioPCMBuffer) throws
    
    /// Finalize current recognition session and flush pending inputs
    func finishTranscribing() async throws
    
    /// Clear all transcript states
    func clear()
}

