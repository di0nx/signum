//
//  PDFTimestamper.swift
//  SignumKit
//
//  Embeds an RFC 3161 token into a PDF as a DocTimeStamp signature using an
//  incremental update. Uses the standard two-pass ByteRange technique: lay the
//  bytes down with a placeholder /Contents, measure the offsets, then splice in
//  the hex-encoded token.
//

import Foundation

/// Errors thrown while embedding a timestamp into a PDF.
public enum PDFTimestampError: Error, LocalizedError {
    case notPDF
    case cannotLocateTrailer
    case embeddingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notPDF: return String(localized: "File is not a valid PDF")
        case .cannotLocateTrailer: return String(localized: "Could not locate the PDF trailer")
        case .embeddingFailed(let reason): return String(localized: "PDF embedding failed: \(reason)")
        }
    }
}

/// Appends a DocTimeStamp signature to a PDF via an incremental update.
///
/// The provided `tsrData` should be a CMS `TimeStampToken` (or a full
/// `TimeStampResp`, from which the token is extracted) that is placed in the
/// signature dictionary's `/Contents`.
///
/// - Note: This produces a structurally valid `/ETSI.RFC3161` DocTimeStamp with
///   a correctly measured `/ByteRange`. A fully PAdES-conformant token must be
///   computed over the `/ByteRange` digest itself; because Signum currently
///   timestamps the original file bytes, the reliable cross-tool verification
///   path remains the `.tsr` sidecar. Binding the token to the `/ByteRange`
///   digest is a planned enhancement.
public struct PDFTimestamper: Timestamper {

    /// Reserved space (in bytes) for the hex-encoded signature contents.
    private static let contentsCapacity = 32 * 1024

    public init() {}

    public func timestamp(fileURL: URL, tsrData: Data) throws -> TimestampOutput {
        let outputURL = fileURL // in-place incremental update; caller controls copies
        let original = try Data(contentsOf: fileURL)
        guard original.starts(with: [0x25, 0x50, 0x44, 0x46]) else {
            throw PDFTimestampError.notPDF
        }

        let token = Self.extractToken(from: tsrData)
        let updated = try Self.buildIncrementalUpdate(original: original, token: token)
        try updated.write(to: outputURL, options: .atomic)

        return TimestampOutput(
            outputURL: outputURL,
            method: String(localized: "Embedded"),
            sidecarURL: nil
        )
    }

    // MARK: - Token extraction

    /// If `tsrData` is a `TimeStampResp`, extract the inner `TimeStampToken`
    /// (a CMS ContentInfo). Otherwise return the input unchanged.
    static func extractToken(from tsrData: Data) -> Data {
        let top = DERParser.parseSequence(tsrData)
        guard let root = top.first else { return tsrData }
        // A bare token's first child is the signedData OID; a response's first
        // child is the PKIStatusInfo SEQUENCE.
        let children = root.children()
        if let first = children.first, first.tagNumber == 0x06 {
            return tsrData // already a ContentInfo
        }
        // Look for the ContentInfo child (the TimeStampToken).
        for child in children where child.isConstructed {
            let sub = child.children()
            if sub.contains(where: { $0.tagNumber == 0x06 }) {
                return child.encoded
            }
        }
        return tsrData
    }

    // MARK: - Incremental update

    private static func buildIncrementalUpdate(original: Data, token: Data) throws -> Data {
        // Determine the next object number and the catalog reference from the trailer.
        let meta = try parseTrailer(original)
        let sigObjNum = meta.size
        let acroFormObjNum = meta.size + 1
        let annotObjNum = meta.size + 2

        // Ensure the appended section starts on a fresh line.
        var out = original
        if out.last != 0x0A { out.append(0x0A) }

        let hexCapacity = contentsCapacity
        let placeholder = String(repeating: "0", count: hexCapacity)

        // --- Pass 1: assemble with a placeholder /Contents and no ByteRange yet.
        // We build the signature object with fixed-width fields so byte offsets
        // are stable between passes.
        func signatureObject(byteRange: String, contentsHex: String) -> String {
            """
            \(sigObjNum) 0 obj
            << /Type /DocTimeStamp /Filter /Adobe.PPKLite /SubFilter /ETSI.RFC3161 \
            /ByteRange \(byteRange) /Contents <\(contentsHex)> >>
            endobj
            """
        }

        let emptyByteRange = "[0 0000000000 0000000000 0000000000]"
        let pass1Sig = signatureObject(byteRange: emptyByteRange, contentsHex: placeholder)

        let sigOffset = out.count
        guard let pass1Data = pass1Sig.data(using: .ascii) else {
            throw PDFTimestampError.embeddingFailed("signature encoding")
        }
        out.append(pass1Data)
        out.append(0x0A)

        // AcroForm + annotation objects that reference the signature field.
        let acroFormOffset = out.count
        let acroForm = """
        \(acroFormObjNum) 0 obj
        << /Fields [\(annotObjNum) 0 R] /SigFlags 3 >>
        endobj
        """
        out.append(Data(acroForm.utf8)); out.append(0x0A)

        let annotOffset = out.count
        let annot = """
        \(annotObjNum) 0 obj
        << /Type /Annot /Subtype /Widget /FT /Sig /T (Signum Timestamp) \
        /Rect [0 0 0 0] /V \(sigObjNum) 0 R /P \(meta.rootRef) >>
        endobj
        """
        out.append(Data(annot.utf8)); out.append(0x0A)

        // Updated catalog referencing the new AcroForm.
        let catalogOffset = out.count
        let catalog = """
        \(meta.rootObjNum) 0 obj
        << /Type /Catalog /AcroForm \(acroFormObjNum) 0 R >>
        endobj
        """
        out.append(Data(catalog.utf8)); out.append(0x0A)

        // --- Cross-reference table (classic xref) chaining to /Prev.
        let xrefOffset = out.count
        let newSize = meta.size + 3
        var xref = "xref\n"
        xref += "\(meta.rootObjNum) 1\n"
        xref += String(format: "%010d 00000 n \n", catalogOffset)
        xref += "\(sigObjNum) 3\n"
        xref += String(format: "%010d 00000 n \n", sigOffset)
        xref += String(format: "%010d 00000 n \n", acroFormOffset)
        xref += String(format: "%010d 00000 n \n", annotOffset)
        out.append(Data(xref.utf8))

        let trailer = """
        trailer
        << /Size \(newSize) /Root \(meta.rootObjNum) 0 R /Prev \(meta.prevXref) >>
        startxref
        \(xrefOffset)
        %%EOF
        """
        out.append(Data(trailer.utf8))

        // --- Pass 2: compute the real ByteRange around /Contents and splice.
        guard let contentsMarker = out.range(of: Data("/Contents <".utf8), options: [], in: sigOffset..<out.count) else {
            throw PDFTimestampError.embeddingFailed("contents marker not found")
        }
        let contentsStart = contentsMarker.upperBound      // first hex digit
        let contentsEnd = contentsStart + hexCapacity       // just past last hex digit
        guard contentsEnd < out.count, out[contentsEnd] == UInt8(ascii: ">") else {
            throw PDFTimestampError.embeddingFailed("contents window mismatch")
        }

        // The ByteRange covers everything except the hex string between the angle
        // brackets: [0, start-of-hex, end-of-hex, remaining-bytes].
        let realByteRange = "[0 \(contentsStart) \(contentsEnd) \(out.count - contentsEnd)]"

        // Overwrite the placeholder ByteRange field (fixed width) with real values.
        guard let brMarker = out.range(of: Data("/ByteRange ".utf8), options: [], in: sigOffset..<out.count) else {
            throw PDFTimestampError.embeddingFailed("byterange marker not found")
        }
        let brFieldStart = brMarker.upperBound
        // The placeholder occupies the exact width of `emptyByteRange`.
        let brFieldEnd = brFieldStart + emptyByteRange.utf8.count
        let paddedByteRange = realByteRange.padding(toLength: emptyByteRange.utf8.count, withPad: " ", startingAt: 0)
        guard brFieldEnd <= out.count else {
            throw PDFTimestampError.embeddingFailed("byterange window mismatch")
        }
        out.replaceSubrange(brFieldStart..<brFieldEnd, with: Data(paddedByteRange.utf8))

        // Splice the hex-encoded token into the reserved /Contents window.
        var hex = token.hexString
        if hex.count > hexCapacity {
            throw PDFTimestampError.embeddingFailed("token exceeds reserved contents capacity")
        }
        hex = hex.padding(toLength: hexCapacity, withPad: "0", startingAt: 0)
        out.replaceSubrange(contentsStart..<contentsEnd, with: Data(hex.utf8))

        return out
    }

    // MARK: - Trailer parsing

    private struct TrailerMeta {
        let size: Int
        let rootObjNum: Int
        let rootRef: String
        let prevXref: Int
    }

    private static func parseTrailer(_ data: Data) throws -> TrailerMeta {
        guard let text = String(data: data.suffix(4096), encoding: .isoLatin1) else {
            throw PDFTimestampError.cannotLocateTrailer
        }
        // startxref offset (points at the current xref, becomes our /Prev).
        let prevXref = Self.lastInt(after: "startxref", in: text) ?? 0

        // Scan the whole document (latin1) for /Size and /Root in a trailer.
        guard let full = String(data: data, encoding: .isoLatin1) else {
            throw PDFTimestampError.cannotLocateTrailer
        }
        let size = Self.lastInt(after: "/Size", in: full) ?? 0
        let rootObjNum = Self.rootObjectNumber(in: full) ?? 0
        guard size > 0, rootObjNum > 0 else {
            throw PDFTimestampError.cannotLocateTrailer
        }
        return TrailerMeta(
            size: size,
            rootObjNum: rootObjNum,
            rootRef: "\(rootObjNum) 0 R",
            prevXref: prevXref
        )
    }

    private static func lastInt(after keyword: String, in text: String) -> Int? {
        var result: Int?
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: keyword, range: searchRange) {
            let tail = text[range.upperBound...].prefix(24)
            let digits = tail.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
            if let value = Int(digits) { result = value }
            searchRange = range.upperBound..<text.endIndex
        }
        return result
    }

    private static func rootObjectNumber(in text: String) -> Int? {
        var result: Int?
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: "/Root", range: searchRange) {
            let tail = text[range.upperBound...].prefix(24)
            let digits = tail.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
            if let value = Int(digits) { result = value }
            searchRange = range.upperBound..<text.endIndex
        }
        return result
    }
}
