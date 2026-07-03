//
//  TSAService.swift
//  SignumKit
//
//  RFC 3161 HTTP transport. Builds a TimeStampReq, POSTs it to a Time Stamp
//  Authority, validates the PKIStatus, and returns the raw TimeStampResp bytes.
//

import Foundation

/// Errors produced while requesting a timestamp from a TSA.
public enum TSAError: Error, LocalizedError {
    case invalidURL(String)
    case network(String)
    case httpStatus(Int)
    case emptyResponse
    case malformedResponse
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return String(localized: "Invalid TSA URL: \(s)")
        case .network(let s): return String(localized: "Network error contacting TSA: \(s)")
        case .httpStatus(let code): return String(localized: "TSA returned HTTP status \(code)")
        case .emptyResponse: return String(localized: "TSA returned an empty response")
        case .malformedResponse: return String(localized: "TSA response could not be parsed")
        case .rejected(let reason): return String(localized: "TSA rejected the request: \(reason)")
        }
    }
}

/// The parsed outcome of a TSA round-trip: the raw token plus the endpoint used.
public struct TSAResponse: Sendable {
    /// The full DER-encoded `TimeStampResp` (i.e. the `.tsr` bytes).
    public let tsrData: Data
    /// The endpoint that produced the token.
    public let usedURL: URL
}

/// Serializes RFC 3161 requests. Modeled as an `actor` so concurrent callers do
/// not hammer the same endpoint simultaneously.
public actor TSAService {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Requests a timestamp token for `fileURL`.
    ///
    /// - Parameters:
    ///   - fileURL: The file to timestamp.
    ///   - tsaURL: The primary TSA endpoint.
    ///   - hashAlgorithm: The digest algorithm for the message imprint.
    ///   - fallbackURL: An optional endpoint tried when the primary fails.
    /// - Returns: The raw `.tsr` bytes and the endpoint that produced them.
    public func requestTimestamp(
        fileURL: URL,
        tsaURL: URL,
        hashAlgorithm: HashAlgorithm,
        fallbackURL: URL?
    ) async throws -> TSAResponse {
        // 1. Hash the file (chunked, off the main memory budget).
        let digest = try await FileHasher().digest(fileURL: fileURL, algorithm: hashAlgorithm)

        // 2. Build the DER request with a random nonce.
        let nonce = UInt64.random(in: UInt64.min...UInt64.max)
        let requestDER = DERBuilder.timeStampRequest(
            digest: digest,
            hashOIDBytes: hashAlgorithm.oidBytes,
            nonce: nonce,
            certReq: true
        )

        // 3. POST to the primary, falling back on any failure.
        do {
            let data = try await post(requestDER, to: tsaURL)
            try Self.validateGranted(data)
            return TSAResponse(tsrData: data, usedURL: tsaURL)
        } catch {
            guard let fallbackURL else { throw error }
            let data = try await post(requestDER, to: fallbackURL)
            try Self.validateGranted(data)
            return TSAResponse(tsrData: data, usedURL: fallbackURL)
        }
    }

    /// Requests a timestamp token for a pre-computed `digest`.
    public func requestTimestamp(
        digest: Data,
        tsaURL: URL,
        hashAlgorithm: HashAlgorithm,
        fallbackURL: URL?
    ) async throws -> TSAResponse {
        let nonce = UInt64.random(in: UInt64.min...UInt64.max)
        let requestDER = DERBuilder.timeStampRequest(
            digest: digest,
            hashOIDBytes: hashAlgorithm.oidBytes,
            nonce: nonce,
            certReq: true
        )
        do {
            let data = try await post(requestDER, to: tsaURL)
            try Self.validateGranted(data)
            return TSAResponse(tsrData: data, usedURL: tsaURL)
        } catch {
            guard let fallbackURL else { throw error }
            let data = try await post(requestDER, to: fallbackURL)
            try Self.validateGranted(data)
            return TSAResponse(tsrData: data, usedURL: fallbackURL)
        }
    }

    // MARK: - HTTP

    private func post(_ body: Data, to url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/timestamp-query", forHTTPHeaderField: "Content-Type")
        request.setValue("application/timestamp-reply", forHTTPHeaderField: "Accept")

        try Task.checkCancellation()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TSAError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TSAError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw TSAError.emptyResponse }
        return data
    }

    // MARK: - PKIStatus validation

    /// Validates the `PKIStatusInfo` at the head of a `TimeStampResp`.
    ///
    /// A granted response begins with `SEQUENCE { PKIStatusInfo { INTEGER 0 } ... }`.
    /// Status `0` = granted, `1` = grantedWithMods; anything else is a rejection.
    static func validateGranted(_ tsr: Data) throws {
        let top = DERParser.parseSequence(tsr)
        guard let response = top.first, response.isConstructed else {
            throw TSAError.malformedResponse
        }
        let children = response.children()
        guard let statusInfo = children.first, statusInfo.isConstructed else {
            throw TSAError.malformedResponse
        }
        let statusFields = statusInfo.children()
        guard let statusInt = statusFields.first,
              let status = DERParser.integer(statusInt) else {
            throw TSAError.malformedResponse
        }

        switch status {
        case 0, 1:
            return // granted / grantedWithMods
        default:
            // Try to surface a human-readable failure string if present.
            var reason = "PKIStatus \(status)"
            for field in statusFields where field.tagNumber == 0x10 { // SEQUENCE (PKIFreeText)
                if let text = field.children().first,
                   let s = String(data: text.content, encoding: .utf8), !s.isEmpty {
                    reason = s
                    break
                }
            }
            throw TSAError.rejected(reason)
        }
    }
}
