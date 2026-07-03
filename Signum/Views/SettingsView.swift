//
//  SettingsView.swift
//  Signum
//

import SwiftUI
import SignumKit

/// The Settings scene (⌘,). Values are stored in the shared App Group suite so
/// the Quick Action extension reads the same configuration.
struct SettingsView: View {
    private static let store = SignumSettings.defaults

    @AppStorage("primaryTSAURL", store: SettingsView.store) private var primaryTSAURL = SignumSettings.defaultPrimaryTSAURL
    @AppStorage("fallbackTSAURL", store: SettingsView.store) private var fallbackTSAURL = SignumSettings.defaultFallbackTSAURL
    @AppStorage("hashAlgorithm", store: SettingsView.store) private var hashAlgorithm = HashAlgorithm.sha256
    @AppStorage("pdfEmbedMode", store: SettingsView.store) private var pdfEmbedMode = EmbedMode.embed
    @AppStorage("officeEmbedMode", store: SettingsView.store) private var officeEmbedMode = EmbedMode.embed
    @AppStorage("notificationsEnabled", store: SettingsView.store) private var notificationsEnabled = true

    var body: some View {
        Form {
            Section {
                HStack {
                    KitsosLogo()
                    VStack(alignment: .leading) {
                        Text("Signum").font(.headline)
                        Text(String(localized: "RFC 3161 Timestamping"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section(String(localized: "Time Stamp Authority")) {
                TextField(String(localized: "Primary TSA URL"), text: $primaryTSAURL)
                TextField(String(localized: "Fallback TSA URL"), text: $fallbackTSAURL)
            }

            Section(String(localized: "Hashing")) {
                Picker(String(localized: "Hash Algorithm"), selection: $hashAlgorithm) {
                    ForEach(HashAlgorithm.allCases) { algo in
                        Text(algo.displayName).tag(algo)
                    }
                }
            }

            Section(String(localized: "Embedding")) {
                Picker(String(localized: "PDF Mode"), selection: $pdfEmbedMode) {
                    Text(String(localized: "Embed in PDF")).tag(EmbedMode.embed)
                    Text(String(localized: ".tsr sidecar")).tag(EmbedMode.sidecar)
                }
                Picker(String(localized: "OOXML/ODF Mode"), selection: $officeEmbedMode) {
                    Text(String(localized: "Embed in file")).tag(EmbedMode.embed)
                    Text(String(localized: ".tsr sidecar")).tag(EmbedMode.sidecar)
                }
            }

            Section(String(localized: "Notifications")) {
                Toggle(String(localized: "Show notifications on success"), isOn: $notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 460)
    }
}

#Preview {
    SettingsView()
}
