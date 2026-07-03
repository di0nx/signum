//
//  SidecarTimestamper.swift
//  SignumKit
//
//  The universal fallback: writes the raw TSA token to a `<file>.tsr` sidecar.
//

import Foundation

/// Writes the timestamp token to a `.tsr` file next to the original. This is the
/// primary strategy for generic files and the fallback for every other format.
public struct SidecarTimestamper: Timestamper {

    public init() {}

    /// Writes `tsrData` to `<fileURL>.tsr` and returns the sidecar location.
    public func timestamp(fileURL: URL, tsrData: Data) throws -> TimestampOutput {
        let sidecarURL = Self.sidecarURL(for: fileURL)
        try tsrData.write(to: sidecarURL, options: .atomic)
        return TimestampOutput(
            outputURL: sidecarURL,
            method: String(localized: "Sidecar (.tsr)"),
            sidecarURL: sidecarURL
        )
    }

    /// The conventional sidecar path for a file: append `.tsr`.
    public static func sidecarURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("tsr")
    }
}
