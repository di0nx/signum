//
//  KitsosLogo.swift
//  Signum
//
//  Loads the Kitsos logo from the CDN with an automatic 50/50 fallback across
//  mirror hosts, and caches decoded images in memory.
//

import SwiftUI

/// Errors from the CDN image pipeline.
enum CDNError: Error {
    case invalidImageData
}

/// Loads images from the Kitsos CDN, retrying on a random mirror if the primary
/// host fails or times out. Modeled as an `actor` so the in-memory cache is
/// accessed serially.
actor CDNImageLoader {
    static let shared = CDNImageLoader()

    private let primary = "https://cdn.kitsos.net"
    private let fallbacks = ["https://cdn2.kitsos.net", "https://cdn3.kitsos.net"]
    private var cache: [String: NSImage] = [:]

    /// Loads the image at `path`, e.g. `/logos/k.png`.
    func load(path: String) async throws -> NSImage {
        if let cached = cache[path] { return cached }

        guard let primaryURL = URL(string: primary + path) else { throw CDNError.invalidImageData }
        let image: NSImage
        do {
            image = try await fetchImage(from: primaryURL)
        } catch {
            let fallback = fallbacks.randomElement() ?? fallbacks[0]
            guard let fallbackURL = URL(string: fallback + path) else { throw CDNError.invalidImageData }
            image = try await fetchImage(from: fallbackURL)
        }
        cache[path] = image
        return image
    }

    private func fetchImage(from url: URL) async throws -> NSImage {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let image = NSImage(data: data) else { throw CDNError.invalidImageData }
        return image
    }
}

/// Displays a CDN-hosted image, falling back to an SF Symbol placeholder while
/// loading or if all mirrors fail.
struct CachedCDNImage: View {
    let path: String
    var fallbackSymbol: String = "seal.fill"

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.kitsosPrimary)
                    .redacted(reason: failed ? [] : .placeholder)
            }
        }
        .task(id: path) {
            failed = false
            do {
                image = try await CDNImageLoader.shared.load(path: path)
            } catch {
                failed = true
            }
        }
    }
}

/// The Kitsos "K" logo, resolving light/dark artwork automatically.
struct KitsosLogo: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        CachedCDNImage(path: colorScheme == .dark ? "/logos/k-dark.png" : "/logos/k.png")
            .frame(width: 32, height: 32)
    }
}

extension Color {
    /// The brand accent color, resolved from the asset catalog (light/dark).
    static let kitsosPrimary = Color("KitsosPrimary")
    static let kitsosBackground = Color("KitsosBackground")
}
