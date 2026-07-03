//
//  OOXMLTimestamper.swift
//  SignumKit
//
//  Embeds a timestamp token into an Office Open XML package (.docx/.xlsx/.pptx)
//  by writing an XML signature part carrying the base64-encoded TSR.
//

import Foundation

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

/// Errors thrown while embedding a timestamp into an OOXML package.
public enum OOXMLTimestampError: Error, LocalizedError {
    case zipUnavailable
    case cannotOpenArchive
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .zipUnavailable: return String(localized: "ZIP support is unavailable")
        case .cannotOpenArchive: return String(localized: "Could not open the Office package")
        case .writeFailed(let reason): return String(localized: "Failed to write signature part: \(reason)")
        }
    }
}

/// Writes a `_xmlsignatures/sig1.xml` package signature part into an OOXML file.
public struct OOXMLTimestamper: Timestamper {

    public init() {}

    public func timestamp(fileURL: URL, tsrData: Data) throws -> TimestampOutput {
        #if canImport(ZIPFoundation)
        guard let archive = Archive(url: fileURL, accessMode: .update) else {
            throw OOXMLTimestampError.cannotOpenArchive
        }

        let isoTime = Self.iso8601(Date())
        let signatureXML = Self.signatureXML(tsrBase64: tsrData.base64EncodedString(), isoTime: isoTime)
        try Self.replaceEntry(in: archive, path: "_xmlsignatures/sig1.xml", data: Data(signatureXML.utf8))

        // Register the signature content type if not already present.
        try Self.ensureContentType(in: archive)

        return TimestampOutput(
            outputURL: fileURL,
            method: String(localized: "Embedded"),
            sidecarURL: nil
        )
        #else
        throw OOXMLTimestampError.zipUnavailable
        #endif
    }

    // MARK: - XML

    static func signatureXML(tsrBase64: String, isoTime: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Signature xmlns="http://www.w3.org/2000/09/xmldsig#" Id="idPackageSignature">
          <SignedInfo>
            <CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/>
            <SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>
          </SignedInfo>
          <SignatureValue/>
          <Object Id="idPackageObject">
            <SignatureProperties>
              <SignatureProperty Id="idSignatureTime" Target="#idPackageSignature">
                <mdssi:SignatureTime xmlns:mdssi="http://schemas.openxmlformats.org/package/2006/digital-signature">
                  <mdssi:Format>YYYY-MM-DDThh:mm:ssTZD</mdssi:Format>
                  <mdssi:Value>\(isoTime)</mdssi:Value>
                </mdssi:SignatureTime>
              </SignatureProperty>
            </SignatureProperties>
            <signum:TimestampToken xmlns:signum="https://kitsos.net/ns/signum">\(tsrBase64)</signum:TimestampToken>
          </Object>
        </Signature>
        """
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    #if canImport(ZIPFoundation)
    /// Removes any existing entry at `path` and adds `data` at that path.
    static func replaceEntry(in archive: Archive, path: String, data: Data) throws {
        if let existing = archive[path] {
            try archive.remove(existing)
        }
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
            let start = data.index(data.startIndex, offsetBy: Int(position))
            let end = data.index(start, offsetBy: size)
            return data.subdata(in: start..<end)
        }
    }

    /// Ensures `[Content_Types].xml` declares the signature part's content type.
    static func ensureContentType(in archive: Archive) throws {
        guard let entry = archive["[Content_Types].xml"] else { return }
        var buffer = Data()
        _ = try? archive.extract(entry, bufferSize: 64 * 1024, skipCRC32: true) { buffer.append($0) }
        guard var text = String(data: buffer, encoding: .utf8) else { return }
        if text.contains("signature+xml") { return }

        let override = "<Override PartName=\"/_xmlsignatures/sig1.xml\" " +
            "ContentType=\"application/vnd.openxmlformats-package.digital-signature-xmlsignature+xml\"/>"
        if let closeRange = text.range(of: "</Types>") {
            text.replaceSubrange(closeRange, with: override + "</Types>")
            try replaceEntry(in: archive, path: "[Content_Types].xml", data: Data(text.utf8))
        }
    }
    #endif
}
