//
//  TimestampResult.swift
//  SignumKit
//

import Foundation

/// The outcome of a successful timestamp operation, persisted to history.
public struct TimestampResult: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let fileName: String
    /// One of "PDF", "OOXML", "ODF", "XML", "Generic".
    public let fileFormat: String
    /// "Embedded" or "Sidecar (.tsr)".
    public let embeddingMethod: String
    /// The sidecar location, or `nil` when the timestamp was embedded.
    public let sidecarURL: URL?
    /// `genTime` extracted from the TSTInfo of the TSA response.
    public let timestampDate: Date
    /// Common Name extracted from the TSA certificate.
    public let tsaName: String
    /// The TSA endpoint that produced the token.
    public let tsaURL: String
    /// "SHA-256" or "SHA-512".
    public let hashAlgorithm: String
    /// The `notAfter` of the TSA certificate, if available.
    public let tsaCertExpiry: Date?
    /// When Signum created this record.
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        fileName: String,
        fileFormat: String,
        embeddingMethod: String,
        sidecarURL: URL?,
        timestampDate: Date,
        tsaName: String,
        tsaURL: String,
        hashAlgorithm: String,
        tsaCertExpiry: Date?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.fileName = fileName
        self.fileFormat = fileFormat
        self.embeddingMethod = embeddingMethod
        self.sidecarURL = sidecarURL
        self.timestampDate = timestampDate
        self.tsaName = tsaName
        self.tsaURL = tsaURL
        self.hashAlgorithm = hashAlgorithm
        self.tsaCertExpiry = tsaCertExpiry
        self.createdAt = createdAt
    }
}
