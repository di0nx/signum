//
//  AboutView.swift
//  Signum
//

import SwiftUI
import AppKit

/// The About window content.
struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 12) {
            KitsosLogo()
                .frame(width: 64, height: 64)
            Text("Signum").font(.title.bold())
            Text(String(localized: "RFC 3161 Timestamping for macOS"))
                .foregroundStyle(.secondary)
            Text(String(localized: "Version \(version)"))
                .font(.caption).foregroundStyle(.secondary)
            Divider().frame(width: 200)
            Text(String(localized: "Part of the Kitsos ecosystem."))
                .font(.caption).foregroundStyle(.secondary)
            Text("© Kitsos / Dion")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 320, height: 300)
    }
}

/// Presents ``AboutView`` in a standalone, reusable window.
enum AboutWindow {
    private static var window: NSWindow?

    @MainActor
    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: AboutView())
        let win = NSWindow(contentViewController: hosting)
        win.title = String(localized: "About Signum")
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        window = win
        win.makeKeyAndOrderFront(nil)
    }
}
