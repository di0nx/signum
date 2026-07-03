//
//  StampView.swift
//  Signum
//

import SwiftUI
import UniformTypeIdentifiers
import SignumKit

/// The Stamp tab: a drop zone, a file queue, and the "Stamp All" action.
struct StampView: View {
    @StateObject private var model = StampViewModel()
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            dropZone

            if !model.items.isEmpty {
                List {
                    ForEach(model.items) { item in
                        StampRow(item: item) { await model.stamp(item) }
                    }
                    .onDelete { indexSet in
                        indexSet.map { model.items[$0] }.forEach(model.remove)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 160)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Button(String(localized: "Choose Files…")) { chooseFiles() }
                if !model.items.isEmpty {
                    Button(String(localized: "Clear"), role: .destructive) { model.clear() }
                }
                Spacer()
                Button {
                    Task { await model.stampAll() }
                } label: {
                    if model.isStamping {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(String(localized: "Stamp All"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.kitsosPrimary)
                .disabled(model.items.isEmpty || model.isStamping)
            }
        }
        .padding()
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isTargeted ? Color.kitsosPrimary : Color.secondary.opacity(0.5))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargeted ? Color.kitsosPrimary.opacity(0.08) : Color.clear)
            )
            .frame(height: 140)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.kitsosPrimary)
                    Text(String(localized: "Drag & drop files to timestamp"))
                        .foregroundStyle(.secondary)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
    }

    // MARK: - Input

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in model.add(urls: urls) }
        }
        return true
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            model.add(urls: panel.urls)
        }
    }
}

/// A single row in the stamp queue showing icon, name, format badge and status.
private struct StampRow: View {
    let item: StampItem
    let retry: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName).lineLimit(1)
                statusLine
            }
            Spacer()
            FormatBadge(format: item.format)
            statusIcon
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var statusLine: some View {
        switch item.status {
        case .idle:
            Text(String(localized: "Ready")).font(.caption).foregroundStyle(.secondary)
        case .stamping:
            Text(String(localized: "Stamping…")).font(.caption).foregroundStyle(.secondary)
        case .success(let result):
            Text(String(localized: "✓ \(Self.format(result.timestampDate)) via \(result.tsaName)"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        case .error(let message):
            HStack(spacing: 6) {
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(1)
                Button(String(localized: "Retry")) { Task { await retry() } }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch item.status {
        case .idle:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .stamping:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

/// A small colored badge naming the detected format.
struct FormatBadge: View {
    let format: FileFormat

    var body: some View {
        Text(format.badge)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.kitsosPrimary.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.kitsosPrimary)
    }
}
