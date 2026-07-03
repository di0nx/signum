//
//  DERParser.swift
//  SignumKit
//
//  A small, non-validating ASN.1 DER reader used to walk RFC 3161 responses
//  and CMS/PKCS#7 structures far enough to extract the fields Signum needs
//  (PKIStatus, genTime, message imprint, embedded certificates).
//

import Foundation

/// A single parsed ASN.1 TLV (tag / length / value) node.
public struct DERNode {
    /// The raw tag octet.
    public let tag: UInt8
    /// The content octets (excluding tag and length).
    public let content: Data
    /// The full range of this node within the parent buffer, tag through content.
    public let range: Range<Data.Index>
    /// The complete TLV bytes (tag + length + content) of this node.
    public let encoded: Data

    /// `true` when the constructed bit (0x20) is set.
    public var isConstructed: Bool { tag & 0x20 != 0 }
    /// The tag with class/constructed bits masked off.
    public var tagNumber: UInt8 { tag & 0x1F }

    /// Parses the children of a constructed node.
    public func children() -> [DERNode] {
        DERParser.parseSequence(content)
    }
}

/// Stateless helpers for reading DER byte streams.
public enum DERParser {

    /// Parses every top-level TLV in `data` in order.
    public static func parseSequence(_ data: Data) -> [DERNode] {
        var nodes: [DERNode] = []
        var index = data.startIndex
        while index < data.endIndex {
            guard let node = parseNode(data, at: index) else { break }
            nodes.append(node)
            index = node.range.upperBound
        }
        return nodes
    }

    /// Parses a single TLV starting at `start` (an index into `data`).
    public static func parseNode(_ data: Data, at start: Data.Index) -> DERNode? {
        guard start < data.endIndex else { return nil }
        let tag = data[start]
        var cursor = data.index(after: start)
        guard cursor < data.endIndex else { return nil }

        let firstLengthByte = data[cursor]
        cursor = data.index(after: cursor)
        var length = 0

        if firstLengthByte & 0x80 == 0 {
            length = Int(firstLengthByte)
        } else {
            let numBytes = Int(firstLengthByte & 0x7F)
            guard numBytes > 0, numBytes <= 8 else { return nil }
            for _ in 0..<numBytes {
                guard cursor < data.endIndex else { return nil }
                length = (length << 8) | Int(data[cursor])
                cursor = data.index(after: cursor)
            }
        }

        let contentStart = cursor
        guard let contentEnd = data.index(contentStart, offsetBy: length, limitedBy: data.endIndex),
              contentEnd <= data.endIndex else { return nil }

        let content = data.subdata(in: contentStart..<contentEnd)
        let encoded = data.subdata(in: start..<contentEnd)
        return DERNode(tag: tag, content: content, range: start..<contentEnd, encoded: encoded)
    }

    // MARK: - Value decoders

    /// Decodes a DER INTEGER's content as an `Int` (best effort, small values).
    public static func integer(_ node: DERNode) -> Int? {
        guard node.tagNumber == 0x02 else { return nil }
        var value = 0
        for byte in node.content { value = (value << 8) | Int(byte) }
        return value
    }

    /// Decodes an ASN.1 `GeneralizedTime` (tag 0x18) content into a `Date`.
    ///
    /// Handles the common forms `YYYYMMDDHHMMSSZ` and fractional-second variants
    /// with a trailing `Z`.
    public static func generalizedTime(_ content: Data) -> Date? {
        guard let string = String(data: content, encoding: .ascii) else { return nil }
        let formats = [
            "yyyyMMddHHmmss'Z'",
            "yyyyMMddHHmmss.SSS'Z'",
            "yyyyMMddHHmmss.SS'Z'",
            "yyyyMMddHHmmss.S'Z'"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    /// Decodes an ASN.1 `UTCTime` (tag 0x17) content into a `Date`.
    public static func utcTime(_ content: Data) -> Date? {
        guard let string = String(data: content, encoding: .ascii) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return formatter.date(from: string)
    }

    /// Recursively searches a node tree for the first node whose tag matches
    /// `tag`, returning its content. Used to locate deeply nested primitives.
    public static func firstDescendant(in nodes: [DERNode], tag: UInt8) -> DERNode? {
        for node in nodes {
            if node.tag == tag { return node }
            if node.isConstructed {
                if let found = firstDescendant(in: node.children(), tag: tag) { return found }
            }
        }
        return nil
    }
}
