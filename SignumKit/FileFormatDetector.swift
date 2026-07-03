//
//  FileFormatDetector.swift
//  SignumKit
//
//  Detects a file's container format from its magic bytes (and, for ZIP
//  containers, the parts inside) rather than trusting the extension alone.
//

import Foundation

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

/// A high-level classification used to select a timestamping strategy.
public enum FileFormat: String, Sendable {
    case pdf = "PDF"
    case ooxml = "OOXML"
    case odf = "ODF"
    case xml = "XML"
    case generic = "Generic"

    /// A short badge label for the UI.
    public var badge: String { rawValue }
}

/// Inspects file bytes to determine the ``FileFormat``.
public struct FileFormatDetector {

    public init() {}

    private static let pdfMagic: [UInt8] = [0x25, 0x50, 0x44, 0x46]           // %PDF
    private static let zipMagic: [UInt8] = [0x50, 0x4B, 0x03, 0x04]           // PK\x03\x04

    /// Detects the format of the file at `url`.
    ///
    /// Only a small prefix is read for the magic-byte checks; ZIP containers are
    /// opened to distinguish OOXML from ODF by their manifest parts.
    public func detect(url: URL) -> FileFormat {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .generic }
        defer { try? handle.close() }

        let header = (try? handle.read(upToCount: 8)) ?? Data()
        let bytes = [UInt8](header)

        if bytes.starts(with: Self.pdfMagic) {
            return .pdf
        }

        if bytes.starts(with: Self.zipMagic) {
            return detectZipContainer(url: url)
        }

        if isXML(header: header) {
            return .xml
        }

        return .generic
    }

    // MARK: - ZIP container discrimination

    private func detectZipContainer(url: URL) -> FileFormat {
        #if canImport(ZIPFoundation)
        guard let archive = Archive(url: url, accessMode: .read) else {
            return .generic
        }
        // ODF: presence of a `mimetype` entry or ODF manifest namespace.
        if let manifest = archive["META-INF/manifest.xml"],
           let content = Self.readEntry(manifest, from: archive),
           content.contains("opendocument") {
            return .odf
        }
        if let mimetype = archive["mimetype"],
           let content = Self.readEntry(mimetype, from: archive),
           content.contains("opendocument") {
            return .odf
        }
        // OOXML: `[Content_Types].xml` referencing the Office namespace.
        if let contentTypes = archive["[Content_Types].xml"],
           let content = Self.readEntry(contentTypes, from: archive),
           content.contains("openxmlformats") {
            return .ooxml
        }
        return .generic
        #else
        // Without ZIPFoundation we can only fall back to extension hints.
        return Self.formatFromExtension(url)
        #endif
    }

    #if canImport(ZIPFoundation)
    private static func readEntry(_ entry: Entry, from archive: Archive) -> String? {
        var buffer = Data()
        _ = try? archive.extract(entry, bufferSize: 64 * 1024, skipCRC32: true) { chunk in
            buffer.append(chunk)
        }
        return String(data: buffer, encoding: .utf8)
    }
    #endif

    private static func formatFromExtension(_ url: URL) -> FileFormat {
        switch url.pathExtension.lowercased() {
        case "docx", "xlsx", "pptx": return .ooxml
        case "odt", "ods", "odp": return .odf
        default: return .generic
        }
    }

    // MARK: - XML sniffing

    private func isXML(header: Data) -> Bool {
        // UTF-8 BOM
        var data = header
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            data = data.dropFirst(3)
        }
        // UTF-16 BOMs
        if header.starts(with: [0xFF, 0xFE]) || header.starts(with: [0xFE, 0xFF]) {
            return true
        }
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<")
    }
}
