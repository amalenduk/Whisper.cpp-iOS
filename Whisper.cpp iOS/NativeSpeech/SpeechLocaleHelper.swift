//
//  SpeechLocaleHelper.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 12/11/26.
//

import Foundation
import Speech

public enum SpeechEngineMode: String, CaseIterable, Identifiable, Sendable {
    case modern = "SpeechAnalyzer"
    case legacy = "SFSpeech"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .modern:
            return "Modern (iOS 26+)"
        case .legacy:
            return "Legacy (SFSpeech)"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .modern:
            return "Modern"
        case .legacy:
            return "Legacy"
        }
    }
}

public struct LocaleItem: Identifiable, Hashable, Sendable {
    public let identifier: String
    public let name: String
    public let isInstalled: Bool
    
    public var id: String { identifier }
    
    public init(identifier: String, name: String, isInstalled: Bool) {
        self.identifier = identifier
        self.name = name
        self.isInstalled = isInstalled
    }
}

public enum SpeechLocaleHelper {
    
    /// Default standard locales shown immediately while dynamic query loads
    public static let defaultLocaleItems: [LocaleItem] = [
        LocaleItem(identifier: "en-US", name: "English (US)", isInstalled: true),
        LocaleItem(identifier: "es-ES", name: "Spanish (Spain)", isInstalled: false),
        LocaleItem(identifier: "fr-FR", name: "French (France)", isInstalled: false),
        LocaleItem(identifier: "de-DE", name: "German (Germany)", isInstalled: false),
        LocaleItem(identifier: "it-IT", name: "Italian (Italy)", isInstalled: false),
        LocaleItem(identifier: "hi-IN", name: "Hindi (India)", isInstalled: false),
        LocaleItem(identifier: "zh-CN", name: "Chinese (Mandarin)", isInstalled: false),
        LocaleItem(identifier: "ja-JP", name: "Japanese (Japan)", isInstalled: false)
    ]
    
    /// Dynamically loads supported locales based on the selected engine and OS capability
    public static func loadSupportedLocales(for engineMode: SpeechEngineMode? = nil) async -> [LocaleItem] {
        let mode = engineMode ?? (isModernSupported ? .modern : .legacy)
        
        if mode == .modern {
            if #available(iOS 26.0, macOS 26.0, *) {
                let supported = await SpeechTranscriber.supportedLocales
                let installed = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
                let current = Locale.current
                
                if !supported.isEmpty {
                    var items = supported.map { loc in
                        let bcp47 = loc.identifier(.bcp47)
                        let name = current.localizedString(forIdentifier: bcp47)
                            ?? loc.localizedString(forIdentifier: bcp47)
                            ?? bcp47
                        let isInstalled = installed.contains(bcp47)
                        return LocaleItem(identifier: bcp47, name: name, isInstalled: isInstalled)
                    }
                    items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    return items
                }
            }
        }
        
        // Fallback or Legacy mode: Query SFSpeechRecognizer supported locales
        let sfLocales = SFSpeechRecognizer.supportedLocales()
        if !sfLocales.isEmpty {
            let current = Locale.current
            var items = sfLocales.map { loc in
                let id = loc.identifier
                let name = current.localizedString(forIdentifier: id)
                    ?? loc.localizedString(forIdentifier: id)
                    ?? id
                return LocaleItem(identifier: id, name: name, isInstalled: true)
            }
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return items
        }
        
        return defaultLocaleItems
    }
    
    public static var isModernSupported: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
        return false
    }
    
    /// Finds the best matching locale among available options.
    /// Handles exact match -> language + region -> language-only match -> fallback.
    public static func findBestMatchingLocale(
        for requestedIdentifier: String,
        in availableIdentifiers: [String]
    ) -> String {
        let normalizedReq = requestedIdentifier.replacingOccurrences(of: "_", with: "-").lowercased()
        
        // 1. Exact match
        if let exact = availableIdentifiers.first(where: {
            $0.replacingOccurrences(of: "_", with: "-").lowercased() == normalizedReq
        }) {
            return exact
        }
        
        // 2. Language code match (e.g. "hi-IN" -> matches any "hi-*")
        let reqComponents = normalizedReq.split(separator: "-")
        if let reqLang = reqComponents.first {
            if let langMatch = availableIdentifiers.first(where: {
                let comp = $0.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
                return comp.first == reqLang
            }) {
                return langMatch
            }
        }
        
        // 3. Fallback to English (US) if available, or first item
        if let enUS = availableIdentifiers.first(where: {
            $0.replacingOccurrences(of: "_", with: "-").lowercased().hasPrefix("en")
        }) {
            return enUS
        }
        
        return availableIdentifiers.first ?? requestedIdentifier
    }
}
