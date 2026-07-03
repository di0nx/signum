//
//  StampViewModel.swift
//  Signum
//

import Foundation
import SwiftUI
import UserNotifications
import SignumKit

/// A file queued for stamping, with its detected format and current status.
struct StampItem: Identifiable {
    enum Status: Equatable {
        case idle
        case stamping
        case success(TimestampResult)
        case error(String)
    }

    let id = UUID()
    let url: URL
    var format: FileFormat
    var status: Status = .idle

    var fileName: String { url.lastPathComponent }
}

/// Drives the Stamp tab: manages the queue, runs stamping, and reports status.
@MainActor
final class StampViewModel: ObservableObject {
    @Published var items: [StampItem] = []
    @Published var isStamping = false
    @Published var errorMessage: String?

    private let coordinator = TimestampCoordinator()
    private let detector = FileFormatDetector()

    /// Adds files to the queue, skipping duplicates and sidecar `.tsr` files.
    func add(urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            let format = detector.detect(url: url)
            items.append(StampItem(url: url, format: format))
        }
    }

    func remove(_ item: StampItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    /// Stamps every idle/errored item, updating status as it goes.
    func stampAll() async {
        guard !isStamping else { return }
        isStamping = true
        errorMessage = nil
        defer { isStamping = false }

        for index in items.indices {
            if case .success = items[index].status { continue }
            items[index].status = .stamping
            do {
                let result = try await coordinator.stamp(fileURL: items[index].url)
                items[index].status = .success(result)
                notify(result)
            } catch is CancellationError {
                items[index].status = .error(String(localized: "Cancelled"))
            } catch {
                items[index].status = .error(error.localizedDescription)
            }
        }
    }

    /// Re-stamps a single item (used by inline retry buttons).
    func stamp(_ item: StampItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].status = .stamping
        do {
            let result = try await coordinator.stamp(fileURL: items[index].url)
            items[index].status = .success(result)
            notify(result)
        } catch {
            items[index].status = .error(error.localizedDescription)
        }
    }

    // MARK: - Notifications

    private func notify(_ result: TimestampResult) {
        guard SignumSettings.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Timestamp added")
        content.body = String(localized: "\(result.fileName) via \(result.tsaName)")
        content.sound = .default
        let request = UNNotificationRequest(identifier: result.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
