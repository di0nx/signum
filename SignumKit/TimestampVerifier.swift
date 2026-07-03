//
//  TimestampVerifier.swift
//  SignumKit
//
//  Parses an RFC 3161 TimeStampResp / TimeStampToken (CMS SignedData), extracts
//  the signed time, message imprint and TSA certificates, re-hashes the original
//  file, and evaluates the certificate chain against the system trust store.
//

import Foundation
import Security

/// Errors produced while verifying a timestamp token.
public enum VerificationError: Error, LocalizedError {
    case malformedToken
    case noMessageImprint
    case noOriginalFile

    public var errorDescription: String? {
        switch self {
        case .malformedToken: return String(localized: "The timestamp token could not be parsed")
        case .noMessageImprint: return String(localized: "No message imprint found in the token")
        case .noOriginalFile: return String(localized: "The original file could not be found for verification")
        }
    }
}

/// Verifies `.tsr` tokens (raw `TimeStampResp` or a bare `TimeStampToken`).
public struct TimestampVerifier {

    // Object identifiers used to locate the encapsulated TSTInfo content.
    private static let idCTTSTInfo: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x10, 0x01, 0x04]
    private static let idSignedData: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]

    public init() {}

    /// Verifies a token against the original file.
    ///
    /// - Parameters:
    ///   - tsrData: Raw `.tsr` bytes (a `TimeStampResp` or `TimeStampToken`).
    ///   - originalFileURL: The file the token is supposed to cover.
    /// - Returns: A populated ``VerificationResult``.
    public func verify(tsrData: Data, originalFileURL: URL) async throws -> VerificationResult {
        guard let token = Self.locateSignedData(in: tsrData) else {
            throw VerificationError.malformedToken
        }

        let tstInfo = Self.extractTSTInfo(from: token)
        let genTime = tstInfo?.genTime
        let (imprintAlgo, imprintHash) = tstInfo.map { ($0.hashAlgorithm, $0.hashedMessage) } ?? (nil, nil)

        // Re-hash the original file with the algorithm named in the imprint.
        let algorithm: HashAlgorithm = (imprintAlgo == .sha512) ? .sha512 : .sha256
        var isValid = false
        var note: String? = nil
        if let imprintHash {
            let computed = try await FileHasher().digest(fileURL: originalFileURL, algorithm: algorithm)
            isValid = (computed == imprintHash)
            if !isValid {
                note = String(localized: "⚠️ File has been modified since timestamp was created")
            }
        } else {
            note = String(localized: "Token contained no message imprint to compare against")
        }

        // Extract and evaluate the TSA certificate chain.
        let certs = Self.extractCertificates(from: token)
        let (tsaName, notBefore, notAfter, trusted) = await Self.evaluateCertificates(certs)
        if trusted == false && isValid {
            note = String(localized: "Timestamp valid but TSA not in system trust store")
        }

        return VerificationResult(
            isValid: isValid,
            timestampDate: genTime,
            tsaName: tsaName,
            tsaCertNotBefore: notBefore,
            tsaCertNotAfter: notAfter,
            hashAlgorithm: (imprintAlgo ?? algorithm).displayName,
            fileHashHex: imprintHash?.hexString,
            trustEvaluated: trusted,
            note: note
        )
    }

    // MARK: - CMS navigation

    /// Locates the SignedData SEQUENCE, whether the input is a full
    /// `TimeStampResp` or a bare `TimeStampToken` (ContentInfo).
    static func locateSignedData(in data: Data) -> DERNode? {
        let top = DERParser.parseSequence(data)
        guard let root = top.first else { return nil }

        // Case A: TimeStampResp = SEQUENCE { PKIStatusInfo, TimeStampToken }.
        // Case B: TimeStampToken = ContentInfo = SEQUENCE { OID signedData, [0] content }.
        func signedData(fromContentInfo info: DERNode) -> DERNode? {
            let children = info.children()
            guard children.contains(where: { $0.tagNumber == 0x06 && $0.content.elementsEqual(idSignedData) }) else {
                return nil
            }
            guard let explicit = children.first(where: { $0.tag == 0xA0 }) else { return nil }
            return explicit.children().first
        }

        // Try treating root directly as a ContentInfo (bare token).
        if let sd = signedData(fromContentInfo: root) { return sd }

        // Otherwise treat root as TimeStampResp and look for the token child.
        for child in root.children() where child.isConstructed {
            if let sd = signedData(fromContentInfo: child) { return sd }
        }
        return nil
    }

    // MARK: - TSTInfo extraction

    struct TSTInfo {
        let genTime: Date?
        let hashAlgorithm: HashAlgorithm?
        let hashedMessage: Data?
    }

    static func extractTSTInfo(from signedData: DERNode) -> TSTInfo? {
        // Find encapContentInfo: a SEQUENCE whose first child is the id-ct-TSTInfo OID.
        for child in signedData.children() where child.isConstructed {
            let sub = child.children()
            guard sub.contains(where: { $0.tagNumber == 0x06 && $0.content.elementsEqual(idCTTSTInfo) }) else {
                continue
            }
            // The [0] explicit wraps an OCTET STRING containing the TSTInfo DER.
            guard let explicit = sub.first(where: { $0.tag == 0xA0 }),
                  let octet = explicit.children().first,
                  octet.tagNumber == 0x04 else { return nil }
            let tstInfoNodes = DERParser.parseSequence(octet.content)
            guard let seq = tstInfoNodes.first else { return nil }
            return parseTSTInfoFields(seq)
        }
        return nil
    }

    private static func parseTSTInfoFields(_ seq: DERNode) -> TSTInfo {
        let fields = seq.children()
        var genTime: Date?
        var algo: HashAlgorithm?
        var hash: Data?

        for field in fields {
            if field.tag == 0x18 { // GeneralizedTime
                genTime = DERParser.generalizedTime(field.content)
            }
            if field.tagNumber == 0x10 && field.isConstructed { // candidate messageImprint SEQUENCE
                let mi = field.children()
                if mi.count == 2,
                   let algoSeq = mi.first, algoSeq.isConstructed,
                   let oid = algoSeq.children().first(where: { $0.tagNumber == 0x06 }),
                   mi.last?.tagNumber == 0x04 {
                    if oid.content.elementsEqual(DERBuilder.sha512OIDBytes) {
                        algo = .sha512
                    } else if oid.content.elementsEqual(DERBuilder.sha256OIDBytes) {
                        algo = .sha256
                    }
                    hash = mi.last?.content
                }
            }
        }
        return TSTInfo(genTime: genTime, hashAlgorithm: algo, hashedMessage: hash)
    }

    // MARK: - Certificates

    static func extractCertificates(from signedData: DERNode) -> [Data] {
        // certificates [0] IMPLICIT is a direct child of SignedData with tag 0xA0.
        for child in signedData.children() where child.tag == 0xA0 {
            let certNodes = child.children().filter { $0.tagNumber == 0x10 && $0.isConstructed }
            if !certNodes.isEmpty {
                return certNodes.map { $0.encoded }
            }
        }
        return []
    }

    static func evaluateCertificates(_ certDERs: [Data]) async -> (name: String?, notBefore: Date?, notAfter: Date?, trusted: Bool) {
        let secCerts = certDERs.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard let leaf = secCerts.first else { return (nil, nil, nil, false) }

        var commonName: CFString?
        SecCertificateCopyCommonName(leaf, &commonName)
        let name = commonName as String?

        // Build a trust object and evaluate against the default policy.
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        SecTrustCreateWithCertificates(secCerts as CFArray, policy, &trust)

        var trusted = false
        if let trust {
            var error: CFError?
            trusted = SecTrustEvaluateWithError(trust, &error)
        }

        let (notBefore, notAfter) = certificateValidity(leaf)
        return (name, notBefore, notAfter, trusted)
    }

    /// Extracts the validity window from a leaf certificate using the macOS-only
    /// `SecCertificateCopyValues` API. Returns `(nil, nil)` if unavailable.
    private static func certificateValidity(_ certificate: SecCertificate) -> (Date?, Date?) {
        let keys = [kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter] as CFArray
        guard let values = SecCertificateCopyValues(certificate, keys, nil) as? [CFString: Any] else {
            return (nil, nil)
        }
        func date(_ oid: CFString) -> Date? {
            guard let entry = values[oid] as? [CFString: Any],
                  let seconds = entry[kSecPropertyKeyValue] as? Double else { return nil }
            // Value is absolute time: seconds since the CF reference date (2001-01-01).
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        return (date(kSecOIDX509V1ValidityNotBefore), date(kSecOIDX509V1ValidityNotAfter))
    }
}

// MARK: - Helpers

extension Data {
    /// Lowercase hex representation of the bytes.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
