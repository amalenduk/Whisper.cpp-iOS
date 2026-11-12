# Native Apple Speech Transcription (iOS 17+ & iOS 26+)

A lightweight, 100% native iOS speech-to-text implementation with **zero third-party dependencies** (no Whisper.cpp, no external C/C++ libraries, no multi-hundred-megabyte GGUF models).

The project features a **dual-engine architecture** managed through **Dependency Injection**, allowing developers to run and test both Apple's next-generation **Modern SpeechAnalyzer** (iOS 26+) and the battle-tested **Legacy SFSpeechRecognizer** (iOS 17+) side by side with an on-the-fly UI switch toggle.

---

## Architecture Overview

```
                          ┌──────────────────────────────┐
                          │   NativeSpeechContentView    │
                          │   (SwiftUI + Switch Button)  │
                          └──────────────┬───────────────┘
                                         │
                          ┌──────────────▼───────────────┐
                          │    NativeSpeechViewModel     │
                          │    (@Observable @MainActor)  │
                          └──────────────┬───────────────┘
                                         │
                        ┌────────────────┴────────────────┐
                        │    SpeechTranscriptionService   │ (Protocol)
                        └────────▲───────────────▲────────┘
                                 │               │
        ┌────────────────────────┴────┐     ┌────┴────────────────────────┐
        │   ModernSpeechTranscriber   │     │    LegacySpeechTranscriber  │
        │      (iOS 26+ Native)       │     │     (iOS 17+ Fallback)      │
        │ SpeechTranscriber + Analyzer│     │      SFSpeechRecognizer     │
        └─────────────────────────────┘     └─────────────────────────────┘
```

---

## Detailed Framework Comparison

| Feature / Metric | Modern Engine (`SpeechAnalyzer`) | Legacy Engine (`SFSpeechRecognizer`) |
| :--- | :--- | :--- |
| **Primary Framework APIs** | `SpeechTranscriber`, `SpeechAnalyzer`, `AssetInventory` | `SFSpeechRecognizer`, `SFSpeechAudioBufferRecognitionRequest`, `SFSpeechRecognitionTask` |
| **Minimum iOS Target** | **iOS 26.0+** (`@available(iOS 26.0, macOS 26.0, *)`) | **iOS 10.0+** (App deployment target: **iOS 17.0**) |
| **Execution Location** | **100% On-Device** (Apple Neural Engine + CoreML) | **Cloud by default** (Apple Servers) / Partial On-Device on select hardware |
| **Internet Requirement** | **Offline after initial model download**.<br>Requires internet connection once to download the on-device language pack via `AssetInventory` (if not pre-installed by the OS). | **Requires active Internet connection by default**.<br>Can attempt `requiresOnDeviceRecognition = true`, but fails if the language or hardware does not support offline recognition. |
| **Session Duration Limit** | **No time limit**.<br>Continuous streaming dictation without arbitrary timeouts because execution is local to device hardware. | **~60 seconds hard limit**.<br>Apple servers terminate recognition after approximately 1 minute of continuous speech with a timeout/quota error unless the session is manually recycled. |
| **Rate & Quota Limits** | **Unlimited**.<br>No server rate limits or daily throttling. | **Restricted**.<br>Subject to Apple’s daily and per-device request quotas when routing through Siri speech servers. |
| **Audio Pipeline Overhead** | **Low**.<br>Requires format conversion via `AVAudioConverter` to `SpeechAnalyzer.bestAvailableAudioFormat` (e.g. 16 kHz Float32/Int16). | **Near Zero**.<br>Direct buffer feed. The native microphone tap buffer is appended directly via `recognitionRequest.append(buffer)` with no conversion overhead. |
| **Token & Segment Granularity** | Character & word-level streaming with volatile vs. finalized state tags and audio time ranges. | Rich `SFTranscriptionSegment` data per token:<br>• `substring` (token string)<br>• `confidence` (0.0 to 1.0)<br>• `timestamp` (TimeInterval)<br>• `duration` (TimeInterval)<br>• `alternativeSubstrings` (candidate tokens) |
| **Language Translation** | **Transcription-focused**.<br>Does not translate speech into another language natively within the recognizer; can be piped into Apple's `Translation.framework` (`TranslationSession`) for live translation. | **Transcription-only**.<br>Transcribes only in the configured locale; no built-in cross-language translation. |
| **Total Supported Locales** | **30 Locales** (on-device neural models) | **63 Locales** (cloud + on-device models) |

---

## Supported Languages Breakdown

### 1. Modern Engine (`SpeechTranscriber` — 30 Locales)
The modern on-device engine supports high-fidelity, on-device neural transcription across major world languages:

```
[fr_CA, fr_CH, fr_FR, fr_BE, ko_KR, pt_PT, pt_BR, de_AT, de_CH, de_DE,
 it_CH, it_IT, zh_CN, zh_TW, es_CL, es_MX, es_ES, es_US, en_CA, en_SG,
 en_GB, en_ZA, en_AU, en_US, en_IE, en_NZ, en_IN, yue_CN, zh_HK, ja_JP]
```

* **English (9)**: US, UK, Canada, Australia, New Zealand, India, Ireland, Singapore, South Africa
* **Spanish (4)**: Spain, Mexico, US, Chile
* **French (4)**: France, Canada, Switzerland, Belgium
* **German (3)**: Germany, Austria, Switzerland
* **Italian (2)**: Italy, Switzerland
* **Portuguese (2)**: Brazil, Portugal
* **Chinese (4)**: Mandarin Simplified (Mainland China), Mandarin Traditional (Taiwan), Cantonese (Mainland China), Cantonese (Hong Kong)
* **Japanese (1)**: Japan
* **Korean (1)**: South Korea

> [!NOTE]
> Hindi (`hi_IN`), Arabic (`ar_SA`), Russian (`ru_RU`), and Scandinavian languages are currently **not** in the 30 on-device locales supported by `SpeechTranscriber` on this SDK version.

---

### 2. Legacy Engine (`SFSpeechRecognizer` — 63 Locales)
The legacy engine provides broader worldwide geographic and linguistic coverage:

```
[en-AU, de-CH, en-PH, sk-SK, en-SG, es-MX, de-AT, ja-JP, el-GR, it-CH,
 en-AE, pt-BR, vi-VN, it-IT, ca-ES, hi-IN-translit, fr-BE, nl-BE, en-US,
 hi-Latn, es-US, zh-HK, tr-TR, es-ES, es-419, hr-HR, ro-RO, en-IN, en-ID,
 pl-PL, fr-CA, fr-CH, fr-FR, en-SA, ko-KR, he-IL, uk-UA, en-ZA, wuu-CN,
 cs-CZ, de-DE, zh-CN, hu-HU, en-IE, zh-TW, sv-SE, da-DK, nl-NL, nb-NO,
 ms-MY, id-ID, th-TH, en-NZ, en-GB, ar-SA, es-CO, hi-IN, en-CA, es-CL,
 ru-RU, yue-CN, pt-PT, fi-FI]
```

#### Languages Available in Legacy but Missing in Modern:
* **Hindi & Indic**: Hindi Devanagari (`hi-IN`), Hinglish / Romanized Hindi (`hi-Latn`), Transliterated Hindi (`hi-IN-translit`).
* **Middle Eastern & Slavic**: Arabic (`ar-SA`), Hebrew (`he-IL`), Russian (`ru-RU`), Ukrainian (`uk-UA`).
* **Southeast Asian**: Vietnamese (`vi-VN`), Thai (`th-TH`), Indonesian (`id-ID`), Malay (`ms-MY`).
* **European**: Dutch (`nl-NL`, `nl-BE`), Polish (`pl-PL`), Turkish (`tr-TR`), Greek (`el-GR`), Czech (`cs-CZ`), Hungarian (`hu-HU`), Romanian (`ro-RO`), Slovak (`sk-SK`), Croatian (`hr-HR`), Catalan (`ca-ES`).
* **Nordic**: Swedish (`sv-SE`), Danish (`da-DK`), Norwegian Bokmål (`nb-NO`), Finnish (`fi-FI`).
* **Regional English**: Philippines (`en-PH`), UAE (`en-AE`), Saudi Arabia (`en-SA`), Indonesia (`en-ID`).
* **Regional Chinese**: Shanghainese / Wu Chinese (`wuu-CN`).

---

## Session Durations & The 60-Second Limitation

### Why Legacy `SFSpeechRecognizer` Stops at ~60 Seconds
1. **Server Quota Enforcement**: Because `SFSpeechRecognizer` streams audio to Apple's speech servers, Apple enforces a strict safety cutoff of approximately **60 seconds per recognition task**.
2. **Failure Mode**: When the limit is reached, the task throws an error (`kAFAssistantErrorDomain error 203` or `216`) and stops transcribing.
3. **Handling**: In applications requiring hours of continuous dictation on older iOS versions, developers must build a cycling mechanism that splits audio into 50-second windows and chains multiple `SFSpeechRecognitionTask` instances together.

### How Modern `SpeechAnalyzer` Solves This
1. **Continuous Local Pipeline**: Because `SpeechAnalyzer` processes audio directly on the Apple Neural Engine without transmitting audio packets to remote servers, there is **no arbitrary 60-second cutoff**.
2. **Memory Efficiency**: The `AsyncStream<AnalyzerInput>` consumes buffers in a producer-consumer model, keeping memory usage constant (~30–45 MB) even over hours of recording.

---

## Internet & Privacy Comparison

```
+-------------------------------------------------------------------------+
|                              MODERN ENGINE                              |
|  [Microphone] -> [AVAudioEngine] -> [SpeechAnalyzer] -> [Neural Engine] |
|                                   |                                     |
|                       100% Local / On-Device                            |
|             (Zero audio packets leave the user's device)                |
+-------------------------------------------------------------------------+

+-------------------------------------------------------------------------+
|                              LEGACY ENGINE                              |
|  [Microphone] -> [AVAudioEngine] -> [SFSpeechRecognizer]                |
|                                            | (HTTPS / gRPC)             |
|                                    [Apple Speech Servers]               |
+-------------------------------------------------------------------------+
```

1. **Modern Engine**:
   * **Privacy**: Guaranteed on-device processing. Microphone audio never leaves the device.
   * **AirPlane Mode**: Functions completely offline once the language model is installed.
   * **Asset Download**: When a user selects a language for the first time, `AssetInventory.assetInstallationRequest` downloads the model package directly from Apple CDN with visual download progress (`downloadProgress`).
2. **Legacy Engine**:
   * **Privacy**: Audio is processed on Apple's cloud servers (subject to user consent in iOS Settings).
   * **AirPlane Mode**: Fails unless on-device speech files were previously cached by Siri/Dictation on supported hardware (A12 Bionic+).

---

## Dependency Injection & Code Architecture

### 1. Protocol Definition (`SpeechTranscriptionService`)
Both engines conform to a unified contract:
```swift
@MainActor
public protocol SpeechTranscriptionService: AnyObject {
    var fullTranscript: String { get }
    var volatileText: String { get }
    var finalizedText: String { get }
    var tokens: [SpeechTranscriptionToken] { get }
    var engineDescription: String { get }
    var isDownloadingModel: Bool { get }
    var downloadProgress: Progress? { get }
    
    func setUpTranscriber(locale: Locale) async throws
    func streamAudioBuffer(_ buffer: AVAudioPCMBuffer) throws
    func finishTranscribing() async throws
    func clear()
}
```

### 2. Service Factory (`SpeechTranscriptionServiceFactory`)
Instantiates the appropriate service based on iOS version or forced legacy mode:
```swift
public enum SpeechTranscriptionServiceFactory {
    public static func makeService(forceLegacy: Bool = false) -> any SpeechTranscriptionService {
        if #available(iOS 26.0, macOS 26.0, *), !forceLegacy {
            return ModernSpeechTranscriber()
        } else {
            return LegacySpeechTranscriber()
        }
    }
}
```

### 3. Smart Locale Matching (`SpeechLocaleHelper`)
Resolves language requests gracefully when switching between engines:
```swift
// Example: If user selects "hi-IN" (Hindi) on Modern, it matches the closest valid fallback.
// When toggled back to Legacy, full "hi-IN" (Devanagari) is immediately selected.
let resolvedID = SpeechLocaleHelper.findBestMatchingLocale(
    for: requestedIdentifier,
    in: availableIdentifiers
)
```

### 4. Interactive Switch Toggle in UI
In [`NativeSpeechContentView.swift`](file:///Users/amal/Desktop/Projects/Whisper.cpp%20iOS/Whisper.cpp%20iOS/NativeSpeech/NativeSpeechContentView.swift), an engine switch card allows instant switching:
```swift
Toggle("", isOn: $viewModel.isUsingModernEngine)
    .labelsHidden()
    .disabled(!viewModel.isModernEngineSupported)
```
When toggled:
1. Ongoing audio recording safely pauses.
2. The active engine swaps from `ModernSpeechTranscriber` to `LegacySpeechTranscriber` (or vice-versa).
3. The language picker dynamically refreshes to display the exact supported locales for that engine (30 vs 63).
4. Audio recording resumes seamlessly if it was active.

---

## How to Build & Run

### Prerequisites
* **macOS 15.0+**
* **Xcode 26.3 or Xcode 27.0**
* **iOS 17.0+ Simulator or Physical Device**

### Command-Line Build
```bash
xcodebuild -project "Whisper.cpp iOS.xcodeproj" \
           -scheme "Whisper.cpp iOS" \
           -destination "generic/platform=iOS Simulator" \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

### Testing Engines on Device
1. Run the app on an **iOS 26+ device or simulator**:
   * Toggle the switch at the top to test **Modern Engine (`SpeechAnalyzer`)**.
   * Toggle the switch OFF to test **Legacy Engine (`SFSpeechRecognizer`)**.
2. Run the app on an **iOS 17–25 device**:
   * The switch is automatically locked to **Legacy Engine** with an explanation indicator.
   * Hindi (`hi-IN`), Arabic, Russian, and 60 other languages are supported via SFSpeech.

