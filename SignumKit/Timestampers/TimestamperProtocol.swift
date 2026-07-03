//
//  TimestamperProtocol.swift
//  SignumKit
//

import Foundation

/// Describes where and how a timestamp token was written.
public struct TimestampOutput: Sendable {
    /// The file that now carries (or is accompanied by) the timestamp.
    public let outputURL: URL
    /// "Embedded" or "Sidecar (.tsr)".
    public let method: String
    /// The sidecar location, or `nil` when embedded in the file itself.
    public let sidecarURL: URL?

    public init(outputURL: URL, method: String, sidecarURL: URL?) {
        self.outputURL = outputURL
        self.method = method
        self.sidecarURL = sidecarURL
    }
}

/// A strategy that writes a TSA token (`tsrData`) into or alongside a file.
public protocol Timestamper {
    /// Applies `tsrData` to the file at `fileURL`.
    /// - Throws: A format-specific error; callers should fall back to the
    ///   universal `.tsr` sidecar on failure.
    /// - Returns: A ``TimestampOutput`` describing the result.
    func timestamp(fileURL: URL, tsrData: Data) throws -> TimestampOutput
}
