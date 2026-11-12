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
    
    /// Compares two locale identifiers for equivalence, ignoring case and hyphen/underscore differences (e.g. "en_US" vs "en-US").
    public static func isEquivalent(_ id1: String, _ id2: String) -> Bool {
        id1.replacingOccurrences(of: "_", with: "-").lowercased() ==
        id2.replacingOccurrences(of: "_", with: "-").lowercased()
    }
    
    /// Finds a matching identifier in a list based on exact match or language prefix match.
    public static func findMatch(for requested: String, in list: [String]) -> String? {
        let normalized = requested.replacingOccurrences(of: "_", with: "-").lowercased()
        
        // 1. Exact match (case & hyphen-insensitive)
        if let exact = list.first(where: { isEquivalent($0, requested) }) {
            return exact
        }
        
        // 2. Language prefix match (e.g. "hi-IN" or "hi-Latn" -> matches "hi-*", "fr-BE" -> "fr-*")
        let components = normalized.split(separator: "-")
        if let lang = components.first, !lang.isEmpty {
            if let langMatch = list.first(where: {
                let comp = $0.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
                return comp.first == lang
            }) {
                return langMatch
            }
        }
        
        return nil
    }
    
    /// Resolves the most appropriate locale when switching engines or initializing.
    ///
    /// Fallback hierarchy:
    /// 1. Currently selected locale (if available or compatible in the new engine)
    /// 2. Device current locale (`Locale.current`, if available in the new engine)
    /// 3. English ("en-US" or any available "en-*")
    /// 4. First available supported locale
    public static func resolveLocaleOnEngineSwitch(
        currentSelection: String,
        availableLocales: [LocaleItem]
    ) -> String {
        guard !availableLocales.isEmpty else {
            return currentSelection
        }
        let availableIds = availableLocales.map { $0.identifier }
        return findBestMatchingLocale(for: currentSelection, in: availableIds)
    }
    
    /// Finds the best matching locale among available options using the fallback hierarchy:
    /// Requested -> Device Locale.current -> English -> First available.
    public static func findBestMatchingLocale(
        for requestedIdentifier: String,
        in availableIdentifiers: [String]
    ) -> String {
        // 1. Check if requested identifier is directly supported (exact or language prefix)
        if let match = findMatch(for: requestedIdentifier, in: availableIdentifiers) {
            return match
        }
        
        // 2. If requested is not available (e.g. Hindi in Modern engine), fallback to device current locale
        let deviceLocaleId = Locale.current.identifier
        if let deviceMatch = findMatch(for: deviceLocaleId, in: availableIdentifiers) {
            return deviceMatch
        }
        
        // 3. If device locale is also not supported, fallback to English ("en-US" or any "en-*")
        if let enUS = availableIdentifiers.first(where: { isEquivalent($0, "en-US") }) {
            return enUS
        }
        if let anyEn = availableIdentifiers.first(where: {
            let normalized = $0.replacingOccurrences(of: "_", with: "-").lowercased()
            return normalized.hasPrefix("en-") || normalized == "en"
        }) {
            return anyEn
        }
        
        // 4. Ultimate fallback to the first available locale
        return availableIdentifiers.first ?? requestedIdentifier
    }
}
