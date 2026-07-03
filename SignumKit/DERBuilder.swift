//
//  DERBuilder.swift
//  SignumKit
//
//  Manual ASN.1 DER encoding for RFC 3161 TimeStampReq structures.
//  No external ASN.1 dependency is required – the request is simple
//  enough to build by hand.
//

import Foundation

/// A collection of stateless helpers that build DER-encoded (ASN.1 Distinguished
/// Encoding Rules) byte sequences.
///
/// Only the primitives required to construct an RFC 3161 `TimeStampReq` are
/// implemented. Every helper returns freshly allocated `Data` and has no shared
/// state, so it is safe to call from any concurrency context.
public enum DERBuilder {

    // MARK: - Well-known OID bytes

    /// Pre-encoded OID body for SHA-256 (`2.16.840.1.101.3.4.2.1`).
    public static let sha256OIDBytes: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]

    /// Pre-encoded OID body for SHA-512 (`2.16.840.1.101.3.4.2.3`).
    public static let sha512OIDBytes: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03]

    // MARK: - Length encoding

    /// Encodes an ASN.1 length using the definite short or long form.
    /// - Parameter length: The number of content octets. Must be non-negative.
    /// - Returns: The DER length octets.
    public static func derLength(_ length: Int) -> Data {
        precondition(length >= 0, "DER length cannot be negative")
        if length < 0x80 {
            return Data([UInt8(length)])
        }
        // Long form: 0x80 | number-of-length-bytes, then the length big-endian.
        var value = length
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }

    // MARK: - Constructed types

    /// Wraps `content` in a SEQUENCE (tag `0x30`).
    public static func derSequence(_ content: Data) -> Data {
        Data([0x30]) + derLength(content.count) + content
    }

    /// Wraps `content` in a SET (tag `0x31`).
    public static func derSet(_ content: Data) -> Data {
        Data([0x31]) + derLength(content.count) + content
    }

    // MARK: - Primitive types

    /// Encodes a non-negative integer as an INTEGER (tag `0x02`).
    public static func derInteger(_ value: Int) -> Data {
        precondition(value >= 0, "Use the Data overload for arbitrary integers")
        if value == 0 {
            return Data([0x02, 0x01, 0x00])
        }
        var v = value
        var bytes: [UInt8] = []
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        // Prepend a leading zero if the high bit is set so the value stays positive.
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0x00, at: 0)
        }
        return Data([0x02]) + derLength(bytes.count) + Data(bytes)
    }

    /// Encodes an arbitrary big-endian byte string as an INTEGER (tag `0x02`).
    ///
    /// A leading `0x00` is prepended when the most-significant bit is set so the
    /// value is interpreted as unsigned/positive. Leading zero bytes are trimmed
    /// to produce minimal DER.
    public static func derInteger(_ value: Data) -> Data {
        var bytes = [UInt8](value)
        // Trim redundant leading zeros (keep at least one byte).
        while bytes.count > 1 && bytes[0] == 0x00 {
            bytes.removeFirst()
        }
        if bytes.isEmpty {
            bytes = [0x00]
        }
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0x00, at: 0)
        }
        return Data([0x02]) + derLength(bytes.count) + Data(bytes)
    }

    /// Encodes an OCTET STRING (tag `0x04`).
    public static func derOctetString(_ data: Data) -> Data {
        Data([0x04]) + derLength(data.count) + data
    }

    /// Encodes a BIT STRING (tag `0x03`). A leading `0x00` "unused bits" octet is
    /// prepended as required by DER for byte-aligned content.
    public static func derBitString(_ data: Data) -> Data {
        let body = Data([0x00]) + data
        return Data([0x03]) + derLength(body.count) + body
    }

    /// Encodes a BOOLEAN (tag `0x01`). DER encodes `true` as `0xFF`.
    public static func derBoolean(_ value: Bool) -> Data {
        Data([0x01, 0x01, value ? 0xFF : 0x00])
    }

    /// Encodes a NULL value (`0x05 0x00`).
    public static func derNull() -> Data {
        Data([0x05, 0x00])
    }

    /// Encodes an OBJECT IDENTIFIER (tag `0x06`) from its pre-encoded body bytes.
    public static func derOID(_ bytes: [UInt8]) -> Data {
        Data([0x06]) + derLength(bytes.count) + Data(bytes)
    }

    // MARK: - Context-specific explicit tags

    /// Wraps `content` in an explicit context tag `[0]` (`0xA0`).
    public static func derExplicitContext0(_ content: Data) -> Data {
        Data([0xA0]) + derLength(content.count) + content
    }

    /// Wraps `content` in an explicit context tag `[1]` (`0xA1`).
    public static func derExplicitContext1(_ content: Data) -> Data {
        Data([0xA1]) + derLength(content.count) + content
    }

    // MARK: - RFC 3161 TimeStampReq

    /// Builds a complete RFC 3161 `TimeStampReq` DER structure.
    ///
    /// ```
    /// SEQUENCE {
    ///   INTEGER 1                          -- version
    ///   SEQUENCE {                         -- messageImprint
    ///     SEQUENCE { OID hashAlg, NULL }   -- hashAlgorithm
    ///     OCTET STRING <digest>            -- hashedMessage
    ///   }
    ///   [0] INTEGER <nonce>                -- nonce
    ///   [1] BOOLEAN TRUE                   -- certReq
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - digest: The message digest of the file to timestamp.
    ///   - hashOIDBytes: Pre-encoded OID body for the hash algorithm.
    ///   - nonce: An unpredictable value echoed back by the TSA.
    ///   - certReq: Whether the TSA should include its certificate in the response.
    /// - Returns: The DER-encoded request suitable for POSTing to a TSA.
    public static func timeStampRequest(
        digest: Data,
        hashOIDBytes: [UInt8],
        nonce: UInt64,
        certReq: Bool
    ) -> Data {
        let hashAlgorithm = derSequence(derOID(hashOIDBytes) + derNull())
        let messageImprint = derSequence(hashAlgorithm + derOctetString(digest))

        var nonceBytes: [UInt8] = []
        var n = nonce
        while n > 0 {
            nonceBytes.insert(UInt8(n & 0xFF), at: 0)
            n >>= 8
        }
        if nonceBytes.isEmpty { nonceBytes = [0x00] }
        let nonceInteger = derInteger(Data(nonceBytes))

        var body = Data()
        body += derInteger(1)                          // version
        body += messageImprint
        body += nonceInteger                            // nonce is a bare INTEGER (implicit)
        body += derBoolean(certReq)                     // certReq
        return derSequence(body)
    }
}
