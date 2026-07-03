//
//  TimestampCoordinator.swift
//  SignumKit
//
//  High-level orchestration shared by the app and the Quick Action extension:
//  detect the format, request a token, embed it (or fall back to a sidecar),
//  record history, and report the result.
//

import Foundation
import Security

/// Drives the end-to-end stamping and verification flows using the shared
/// settings, so both the main app and the extension behave identically.
public struct TimestampCoordinator {

    private let tsaService: TSAService
    private let detector = FileFormatDetector()

    public init(tsaService: TSAService = TSAService()) {
        self.tsaService = tsaService
    }

    /// Timestamps a single file end-to-end, honoring the shared settings.
    ///
    /// - Parameter fileURL: The file to timestamp.
    /// - Returns: A ``TimestampResult`` (also appended to shared history).
    @discardableResult
    public func stamp(fileURL: URL) async throws -> TimestampResult {
        let format = detector.detect(url: fileURL)
        let hashAlgorithm = SignumSettings.hashAlgorithm

        guard let primaryURL = URL(string: SignumSettings.primaryTSAURL) else {
            throw TSAError.invalidURL(SignumSettings.primaryTSAURL)
        }
        let fallbackURL = URL(string: SignumSettings.fallbackTSAURL)

        // 1. Obtain the token.
        let response = try await tsaService.requestTimestamp(
            fileURL: fileURL,
            tsaURL: primaryURL,
            hashAlgorithm: hashAlgorithm,
            fallbackURL: fallbackURL
        )

        // 2. Choose and apply an embedding strategy, falling back to a sidecar.
        let (output, note) = applyToken(response.tsrData, fileURL: fileURL, format: format)

        // 3. Derive display metadata from the token.
        let tokenInfo = TimestampVerifier.locateSignedData(in: response.tsrData)
            .flatMap { TimestampVerifier.extractTSTInfo(from: $0) }
        let certName = TimestampVerifier.locateSignedData(in: response.tsrData)
            .map { TimestampVerifier.extractCertificates(from: $0) }
            .flatMap { $0.first }
            .flatMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            .flatMap { cert -> String? in
                var cn: CFString?
                SecCertificateCopyCommonName(cert, &cn)
                return cn as String?
            }

        let result = TimestampResult(
            fileURL: fileURL,
            fileName: fileURL.lastPathComponent,
            fileFormat: format.rawValue,
            embeddingMethod: output.method,
            sidecarURL: output.sidecarURL,
            timestampDate: tokenInfo?.genTime ?? Date(),
            tsaName: certName ?? Self.host(of: response.usedURL),
            tsaURL: response.usedURL.absoluteString,
            hashAlgorithm: hashAlgorithm.displayName,
            tsaCertExpiry: nil
        )
        SignumSettings.appendHistory(result)
        _ = note
        return result
    }

    /// Verifies a file, auto-selecting the token source.
    public func verify(fileURL: URL) async throws -> VerificationResult {
        let sidecar = SidecarTimestamper.sidecarURL(for: fileURL)
        if FileManager.default.fileExists(atPath: sidecar.path) {
            let tsr = try Data(contentsOf: sidecar)
            return try await TimestampVerifier().verify(tsrData: tsr, originalFileURL: fileURL)
        }
        // If the file itself is a `.tsr`, verify it against its sibling original.
        if fileURL.pathExtension.lowercased() == "tsr" {
            let original = fileURL.deletingPathExtension()
            let tsr = try Data(contentsOf: fileURL)
            return try await TimestampVerifier().verify(tsrData: tsr, originalFileURL: original)
        }
        throw VerificationError.noOriginalFile
    }

    // MARK: - Strategy selection

    private func applyToken(_ tsr: Data, fileURL: URL, format: FileFormat) -> (TimestampOutput, String?) {
        let sidecar = SidecarTimestamper()

        func embedOrSidecar(_ timestamper: Timestamper, mode: EmbedMode, failureNote: String) -> (TimestampOutput, String?) {
            guard mode == .embed else {
                let out = (try? sidecar.timestamp(fileURL: fileURL, tsrData: tsr))
                return (out ?? Self.fallbackOutput(fileURL), nil)
            }
            do {
                return (try timestamper.timestamp(fileURL: fileURL, tsrData: tsr), nil)
            } catch {
                let out = (try? sidecar.timestamp(fileURL: fileURL, tsrData: tsr)) ?? Self.fallbackOutput(fileURL)
                return (out, failureNote)
            }
        }

        switch format {
        case .pdf:
            return embedOrSidecar(PDFTimestamper(), mode: SignumSettings.pdfEmbedMode,
                                  failureNote: String(localized: "PDF embedding failed, saved as .tsr sidecar"))
        case .ooxml:
            return embedOrSidecar(OOXMLTimestamper(), mode: SignumSettings.officeEmbedMode,
                                  failureNote: String(localized: "Office embedding failed, saved as .tsr sidecar"))
        case .odf:
            return embedOrSidecar(ODFTimestamper(), mode: SignumSettings.officeEmbedMode,
                                  failureNote: String(localized: "Office embedding failed, saved as .tsr sidecar"))
        case .xml:
            return embedOrSidecar(XMLTimestamper(), mode: SignumSettings.officeEmbedMode,
                                  failureNote: String(localized: "XML embedding failed, saved as .tsr sidecar"))
        case .generic:
            let out = (try? sidecar.timestamp(fileURL: fileURL, tsrData: tsr)) ?? Self.fallbackOutput(fileURL)
            return (out, nil)
        }
    }

    private static func fallbackOutput(_ fileURL: URL) -> TimestampOutput {
        let url = SidecarTimestamper.sidecarURL(for: fileURL)
        return TimestampOutput(outputURL: url, method: String(localized: "Sidecar (.tsr)"), sidecarURL: url)
    }

    private static func host(of url: URL) -> String {
        url.host ?? url.absoluteString
    }
}
