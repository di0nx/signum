//
//  VerifyViewModel.swift
//  Signum
//

import Foundation
import SwiftUI
import SignumKit

/// Drives the Verify tab: takes a dropped/selected file and reports the result.
@MainActor
final class VerifyViewModel: ObservableObject {
    @Published var fileURL: URL?
    @Published var result: VerificationResult?
    @Published var isVerifying = false
    @Published var errorMessage: String?

    private let coordinator = TimestampCoordinator()

    var fileName: String? { fileURL?.lastPathComponent }

    func setFile(_ url: URL) {
        fileURL = url
        result = nil
        errorMessage = nil
        Task { await verify() }
    }

    func verify() async {
        guard let fileURL else { return }
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }
        do {
            result = try await coordinator.verify(fileURL: fileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
