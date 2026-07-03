//
//  SignumSettings.swift
//  SignumKit
//
//  Shared configuration persisted in the App Group so the main app and the
//  Quick Action extension read/write the same values.
//

import Foundation

/// The hash algorithm used to build the message imprint.
public enum HashAlgorithm: String, Codable, CaseIterable, Identifiable, Sendable {
    case sha256
    case sha512

    public var id: String { rawValue }

    /// Human-readable name, e.g. "SHA-256".
    public var displayName: String {
        switch self {
        case .sha256: return "SHA-256"
        case .sha512: return "SHA-512"
        }
    }

    /// Pre-encoded ASN.1 OID body for this algorithm.
    public var oidBytes: [UInt8] {
        switch self {
        case .sha256: return DERBuilder.sha256OIDBytes
        case .sha512: return DERBuilder.sha512OIDBytes
        }
    }
}

/// Whether format-aware timestamps are embedded in the file or written to a
/// `.tsr` sidecar.
public enum EmbedMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case embed
    case sidecar

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .embed: return String(localized: "Embed in file")
        case .sidecar: return String(localized: ".tsr sidecar")
        }
    }
}

/// Namespaced accessors for Signum's shared settings, backed by the App Group
/// `UserDefaults` suite so the extension and app stay in sync.
public enum SignumSettings {

    /// The App Group identifier shared by all Signum targets.
    public static let appGroupID = "group.net.kitsos.signum"

    /// The shared defaults suite. Falls back to `.standard` if the App Group is
    /// unavailable (e.g. during unit tests without the entitlement).
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private enum Key {
        static let primaryTSAURL = "primaryTSAURL"
        static let fallbackTSAURL = "fallbackTSAURL"
        static let hashAlgorithm = "hashAlgorithm"
        static let pdfEmbedMode = "pdfEmbedMode"
        static let officeEmbedMode = "officeEmbedMode"
        static let notificationsEnabled = "notificationsEnabled"
        static let history = "stampHistory"
    }

    // MARK: - Defaults

    public static let defaultPrimaryTSAURL = "http://timestamp.digicert.com"
    public static let defaultFallbackTSAURL = "https://rfc3161.ai.moda"

    // MARK: - Accessors

    public static var primaryTSAURL: String {
        get { defaults.string(forKey: Key.primaryTSAURL) ?? defaultPrimaryTSAURL }
        set { defaults.set(newValue, forKey: Key.primaryTSAURL) }
    }

    public static var fallbackTSAURL: String {
        get { defaults.string(forKey: Key.fallbackTSAURL) ?? defaultFallbackTSAURL }
        set { defaults.set(newValue, forKey: Key.fallbackTSAURL) }
    }

    public static var hashAlgorithm: HashAlgorithm {
        get { defaults.string(forKey: Key.hashAlgorithm).flatMap(HashAlgorithm.init) ?? .sha256 }
        set { defaults.set(newValue.rawValue, forKey: Key.hashAlgorithm) }
    }

    public static var pdfEmbedMode: EmbedMode {
        get { defaults.string(forKey: Key.pdfEmbedMode).flatMap(EmbedMode.init) ?? .embed }
        set { defaults.set(newValue.rawValue, forKey: Key.pdfEmbedMode) }
    }

    public static var officeEmbedMode: EmbedMode {
        get { defaults.string(forKey: Key.officeEmbedMode).flatMap(EmbedMode.init) ?? .embed }
        set { defaults.set(newValue.rawValue, forKey: Key.officeEmbedMode) }
    }

    public static var notificationsEnabled: Bool {
        get { defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    // MARK: - History persistence

    private static let maxHistoryEntries = 500

    /// Loads the persisted timestamp history, newest first.
    public static func loadHistory() -> [TimestampResult] {
        guard let data = defaults.data(forKey: Key.history) else { return [] }
        return (try? JSONDecoder().decode([TimestampResult].self, from: data)) ?? []
    }

    /// Persists `history`, trimming to the most recent ``maxHistoryEntries``.
    public static func saveHistory(_ history: [TimestampResult]) {
        let trimmed = Array(history.prefix(maxHistoryEntries))
        if let data = try? JSONEncoder().encode(trimmed) {
            defaults.set(data, forKey: Key.history)
        }
    }

    /// Prepends a new result to the history and persists it.
    public static func appendHistory(_ result: TimestampResult) {
        var history = loadHistory()
        history.insert(result, at: 0)
        saveHistory(history)
    }

    /// Removes all persisted history.
    public static func clearHistory() {
        defaults.removeObject(forKey: Key.history)
    }
}
