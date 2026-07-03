//
//  XMLTimestamper.swift
//  SignumKit
//
//  Adds a XAdES-style enveloped signature carrying an RFC 3161 timestamp to a
//  standalone XML document. No asymmetric signature is produced – only the
//  timestamp token is embedded in <xades:EncapsulatedTimeStamp>.
//

import Foundation

/// Errors thrown while embedding a timestamp into an XML document.
public enum XMLTimestampError: Error, LocalizedError {
    case cannotParse
    case cannotSerialize

    public var errorDescription: String? {
        switch self {
        case .cannotParse: return String(localized: "The XML document could not be parsed")
        case .cannotSerialize: return String(localized: "The XML document could not be written")
        }
    }
}

/// Appends an enveloped `<ds:Signature>` element carrying the timestamp token.
public struct XMLTimestamper: Timestamper {

    private static let dsNS = "http://www.w3.org/2000/09/xmldsig#"
    private static let xadesNS = "http://uri.etsi.org/01903/v1.3.2#"
    private static let signumNS = "https://kitsos.net/ns/signum"

    public init() {}

    public func timestamp(fileURL: URL, tsrData: Data) throws -> TimestampOutput {
        let document: XMLDocument
        do {
            document = try XMLDocument(contentsOf: fileURL, options: [.nodePreserveWhitespace])
        } catch {
            throw XMLTimestampError.cannotParse
        }
        guard let root = document.rootElement() else {
            throw XMLTimestampError.cannotParse
        }

        let signature = Self.buildSignatureElement(tsrBase64: tsrData.base64EncodedString())
        root.addChild(signature)

        let output = document.xmlData(options: [.nodePrettyPrint])
        do {
            try output.write(to: fileURL, options: .atomic)
        } catch {
            throw XMLTimestampError.cannotSerialize
        }

        return TimestampOutput(
            outputURL: fileURL,
            method: String(localized: "Embedded"),
            sidecarURL: nil
        )
    }

    // MARK: - Element construction

    static func buildSignatureElement(tsrBase64: String) -> XMLElement {
        let signature = XMLElement(name: "ds:Signature")
        signature.addAttribute(XMLNode.attribute(withName: "xmlns:ds", stringValue: dsNS) as! XMLNode)

        let signatureValue = XMLElement(name: "ds:SignatureValue")
        signature.addChild(signatureValue)

        let object = XMLElement(name: "ds:Object")
        let qualifying = XMLElement(name: "xades:QualifyingProperties")
        qualifying.addAttribute(XMLNode.attribute(withName: "xmlns:xades", stringValue: xadesNS) as! XMLNode)

        let unsigned = XMLElement(name: "xades:UnsignedSignatureProperties")
        let sigTimestamp = XMLElement(name: "xades:SignatureTimestamp")
        let encapsulated = XMLElement(name: "xades:EncapsulatedTimeStamp", stringValue: tsrBase64)

        sigTimestamp.addChild(encapsulated)
        unsigned.addChild(sigTimestamp)
        qualifying.addChild(unsigned)
        object.addChild(qualifying)
        signature.addChild(object)
        return signature
    }
}
