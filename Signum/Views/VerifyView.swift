//
//  VerifyView.swift
//  Signum
//

import SwiftUI
import UniformTypeIdentifiers
import SignumKit

/// The Verify tab: drop a file (or its `.tsr`) and see the verification verdict.
struct VerifyView: View {
    @StateObject private var model = VerifyViewModel()
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            dropZone

            if model.isVerifying {
                ProgressView(String(localized: "Verifying…"))
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if let result = model.result {
                resultCard(result)
            }

            HStack {
                Button(String(localized: "Choose File…")) { chooseFile() }
                Spacer()
            }
        }
        .padding()
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isTargeted ? Color.kitsosPrimary : Color.secondary.opacity(0.5))
            .frame(height: 120)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.kitsosPrimary)
                    Text(model.fileName ?? String(localized: "Drop a file to verify its timestamp"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                providers.first?.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in model.setFile(url) } }
                }
                return true
            }
    }

    private func resultCard(_ result: VerificationResult) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if result.isValid {
                        Label(String(localized: "Valid"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green).font(.headline)
                    } else {
                        Label(String(localized: "Invalid"), systemImage: "xmark.seal.fill")
                            .foregroundStyle(.red).font(.headline)
                    }
                    Spacer()
                }
                Divider()
                row(String(localized: "Timestamp"), Self.format(result.timestampDate))
                row(String(localized: "TSA"), result.tsaName ?? "—")
                if let nb = result.tsaCertNotBefore, let na = result.tsaCertNotAfter {
                    row(String(localized: "Cert validity"), "\(Self.format(nb)) – \(Self.format(na))")
                }
                row(String(localized: "Hash algorithm"), result.hashAlgorithm ?? "—")
                row(String(localized: "File hash"), result.truncatedHashHex ?? "—")
                if let note = result.note {
                    Label(note, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(result.isValid ? .orange : .red)
                }
            }
            .padding(6)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            model.setFile(url)
        }
    }

    private static func format(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
