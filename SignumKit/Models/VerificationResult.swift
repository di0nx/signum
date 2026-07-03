//
//  VerificationResult.swift
//  SignumKit
//

import Foundation

/// The result of verifying a timestamp token against its original file.
public struct VerificationResult: Identifiable, Sendable {
    public let id = UUID()

    /// Overall verdict: the file hash matches the token's message imprint.
    public let isValid: Bool
    /// `genTime` from the TSTInfo.
    public let timestampDate: Date?
    /// TSA name derived from the signing certificate's Common Name.
    public let tsaName: String?
    /// Validity window of the TSA certificate.
    public let tsaCertNotBefore: Date?
    public let tsaCertNotAfter: Date?
    /// The hash algorithm named in the message imprint, e.g. "SHA-256".
    public let hashAlgorithm: String?
    /// The imprinted file hash, hex-encoded.
    public let fileHashHex: String?
    /// `true` when the cert chain evaluated to a system-trusted anchor.
    public let trustEvaluated: Bool
    /// A human-readable note surfaced to the UI (warnings / context).
    public let note: String?

    public init(
        isValid: Bool,
        timestampDate: Date?,
        tsaName: String?,
        tsaCertNotBefore: Date?,
        tsaCertNotAfter: Date?,
        hashAlgorithm: String?,
        fileHashHex: String?,
        trustEvaluated: Bool,
        note: String?
    ) {
        self.isValid = isValid
        self.timestampDate = timestampDate
        self.tsaName = tsaName
        self.tsaCertNotBefore = tsaCertNotBefore
        self.tsaCertNotAfter = tsaCertNotAfter
        self.hashAlgorithm = hashAlgorithm
        self.fileHashHex = fileHashHex
        self.trustEvaluated = trustEvaluated
        self.note = note
    }

    /// The file hash truncated to 16 characters with an ellipsis, for display.
    public var truncatedHashHex: String? {
        guard let hex = fileHashHex else { return nil }
        return hex.count > 16 ? String(hex.prefix(16)) + "…" : hex
    }
}
