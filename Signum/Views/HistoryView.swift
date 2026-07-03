//
//  HistoryView.swift
//  Signum
//

import SwiftUI
import SignumKit

/// The History tab: a persistent log of all timestamps created by Signum.
struct HistoryView: View {
    @State private var history: [TimestampResult] = []

    var body: some View {
        VStack {
            if history.isEmpty {
                ContentUnavailableCompat(
                    title: String(localized: "No timestamps yet"),
                    systemImage: "clock",
                    description: String(localized: "Stamped files will appear here.")
                )
            } else {
                List(history) { result in
                    HStack(spacing: 12) {
                        Image(systemName: "seal.fill").foregroundStyle(Color.kitsosPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.fileName).lineLimit(1)
                            Text("\(Self.format(result.timestampDate)) · \(result.tsaName)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        FormatBadge(format: FileFormat(rawValue: result.fileFormat) ?? .generic)
                        Text(result.embeddingMethod)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }

            HStack {
                Spacer()
                Button(String(localized: "Clear History"), role: .destructive) {
                    SignumSettings.clearHistory()
                    history = []
                }
                .disabled(history.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding()
        .onAppear { history = SignumSettings.loadHistory() }
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

/// A minimal `ContentUnavailableView` stand-in that also works on macOS 13.
struct ContentUnavailableCompat: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(description).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
