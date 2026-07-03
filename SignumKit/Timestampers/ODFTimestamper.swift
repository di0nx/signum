//
//  ODFTimestamper.swift
//  SignumKit
//
//  Embeds a timestamp token into an OpenDocument package (.odt/.ods/.odp) by
//  writing a META-INF/documentsignatures.xml part with the base64-encoded TSR.
//

import Foundation

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

/// Errors thrown while embedding a timestamp into an ODF package.
public enum ODFTimestampError: Error, LocalizedError {
    case zipUnavailable
    case cannotOpenArchive

    public var errorDescription: String? {
        switch self {
        case .zipUnavailable: return String(localized: "ZIP support is unavailable")
        case .cannotOpenArchive: return String(localized: "Could not open the OpenDocument package")
        }
    }
}

/// Writes `META-INF/documentsignatures.xml` into an ODF package.
public struct ODFTimestamper: Timestamper {

    public init() {}

    public func timestamp(fileURL: URL, tsrData: Data) throws -> TimestampOutput {
        #if canImport(ZIPFoundation)
        guard let archive = Archive(url: fileURL, accessMode: .update) else {
            throw ODFTimestampError.cannotOpenArchive
        }
        let xml = Self.documentSignaturesXML(tsrBase64: tsrData.base64EncodedString())
        try OOXMLTimestamper.replaceEntry(in: archive, path: "META-INF/documentsignatures.xml", data: Data(xml.utf8))
        return TimestampOutput(
            outputURL: fileURL,
            method: String(localized: "Embedded"),
            sidecarURL: nil
        )
        #else
        throw ODFTimestampError.zipUnavailable
        #endif
    }

    static func documentSignaturesXML(tsrBase64: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <document-signatures xmlns="urn:oasis:names:tc:opendocument:xmlns:digitalsig:1.0">
          <Signature xmlns="http://www.w3.org/2000/09/xmldsig#" Id="SignumTimestamp">
            <SignedInfo>
              <CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/>
              <SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>
            </SignedInfo>
            <SignatureValue/>
            <Object>
              <signum:TimestampToken xmlns:signum="https://kitsos.net/ns/signum">\(tsrBase64)</signum:TimestampToken>
            </Object>
          </Signature>
        </document-signatures>
        """
    }
}
