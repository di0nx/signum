//
//  FileHasher.swift
//  SignumKit
//
//  Chunked, async SHA-256 / SHA-512 hashing so that very large files can be
//  hashed without loading them entirely into memory.
//

import Foundation
import CryptoKit

/// Errors thrown while hashing a file.
public enum FileHashError: Error, LocalizedError {
    case cannotOpenFile(URL)
    case readFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .cannotOpenFile(let url):
            return String(localized: "Cannot access file – try dragging from Finder: \(url.lastPathComponent)")
        case .readFailed(let url):
            return String(localized: "Failed to read file: \(url.lastPathComponent)")
        }
    }
}

/// Hashes files in fixed-size chunks so memory use stays flat regardless of
/// file size, and reports progress through an `AsyncStream`.
public struct FileHasher {

    /// The chunk size used for streamed reads (512 KB).
    public static let chunkSize = 512 * 1024

    public init() {}

    /// Computes the SHA-256 digest of the file at `fileURL`.
    /// - Parameters:
    ///   - fileURL: The file to hash.
    ///   - progress: Optional continuation that receives a `0.0...1.0` fraction.
    /// - Returns: The 32-byte digest.
    public func sha256(fileURL: URL, progress: ((Double) -> Void)? = nil) async throws -> Data {
        var hasher = SHA256()
        try await stream(fileURL: fileURL, progress: progress) { chunk in
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }

    /// Computes the SHA-512 digest of the file at `fileURL`.
    public func sha512(fileURL: URL, progress: ((Double) -> Void)? = nil) async throws -> Data {
        var hasher = SHA512()
        try await stream(fileURL: fileURL, progress: progress) { chunk in
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }

    /// Computes the digest for the given ``HashAlgorithm``.
    public func digest(fileURL: URL, algorithm: HashAlgorithm, progress: ((Double) -> Void)? = nil) async throws -> Data {
        switch algorithm {
        case .sha256: return try await sha256(fileURL: fileURL, progress: progress)
        case .sha512: return try await sha512(fileURL: fileURL, progress: progress)
        }
    }

    // MARK: - Private

    private func stream(
        fileURL: URL,
        progress: ((Double) -> Void)?,
        consume: (Data) -> Void
    ) async throws {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw FileHashError.cannotOpenFile(fileURL)
        }
        defer { try? handle.close() }

        let total = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        var processed = 0

        while true {
            try Task.checkCancellation()
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: Self.chunkSize) ?? Data()
            } catch {
                throw FileHashError.readFailed(fileURL)
            }
            if chunk.isEmpty { break }
            consume(chunk)
            processed += chunk.count
            if total > 0 {
                progress?(min(1.0, Double(processed) / Double(total)))
            }
            // Yield so a tight loop over a large file stays cooperative.
            await Task.yield()
        }
        progress?(1.0)
    }
}
