# Changelog

All notable changes to Signum are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.1.0] - Initial Release

### Added
- Native macOS SwiftUI app (**Signum**) targeting macOS 13+.
- **SignumKit** framework with a from-scratch RFC 3161 implementation:
  - Manual ASN.1 DER encoder (`DERBuilder`) and reader (`DERParser`).
  - `TSAService` actor: builds `TimeStampReq`, POSTs to a TSA, validates
    `PKIStatus`, with automatic fallback to a secondary endpoint.
  - `TimestampVerifier`: parses the token, re-hashes the file, and evaluates the
    TSA certificate chain against the system trust store.
  - Chunked, cancellable `FileHasher` (SHA-256 / SHA-512) with progress.
  - Magic-byte `FileFormatDetector` (PDF / OOXML / ODF / XML / Generic).
- Format-aware timestampers with universal `.tsr` sidecar fallback:
  PDF `DocTimeStamp` incremental update, OOXML/ODF package signatures, XAdES XML.
- Main window with **Stamp**, **Verify**, and **History** tabs; drag & drop and
  `NSOpenPanel` file selection; success notifications.
- **Finder Quick Action** extension for stamping/verifying from the right-click menu.
- Settings (⌘,) for TSA URLs, hash algorithm, per-format embedding mode, and
  notifications — shared with the extension via the App Group.
- CDN-backed `KitsosLogo` view with primary/mirror fallback and in-memory cache.
- Light/dark brand theming via asset-catalog colors.
- Unit tests for the DER primitives, parser, and file hashing.
- Localization scaffolding (English base + German stub).

[0.1.0]: https://github.com/di0nx/signum/releases/tag/v0.1.0
