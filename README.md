<div align="center">

# Signum

**RFC 3161 Timestamping for macOS**

<sub>Part of the Kitsos personal infrastructure ecosystem.</sub>

</div>

---

Signum is a native macOS app that cryptographically timestamps files against a
trusted RFC 3161 Time Stamp Authority (TSA). A timestamp proves that a file
existed in its exact form at a specific point in time, attested by a trusted
third party — without revealing the file's contents to that party (only a hash
is sent). You can stamp files from the main window via drag & drop, or straight
from Finder with a right-click Quick Action.

## Features

- **Drag & drop stamping** of any file, individually or in batches.
- **Finder Quick Action** — "Add Timestamp" / "Verify Timestamp" without opening the app.
- **Format-aware embedding** — the token is written into the document where the
  format supports it, otherwise saved as a universal `.tsr` sidecar.
- **Verification** — re-hash the original and validate the token, TSA identity,
  and certificate trust.
- **History** — a persistent log of everything you've stamped.
- Full **light/dark mode**, native SwiftUI, sandboxed.

## Supported formats

| Format | Detection | Default strategy | Fallback |
|---|---|---|---|
| **PDF** | `%PDF` magic | Incremental-update `DocTimeStamp` (`/ETSI.RFC3161`) | `.tsr` sidecar |
| **OOXML** (`.docx`/`.xlsx`/`.pptx`) | ZIP + `openxmlformats` in `[Content_Types].xml` | `_xmlsignatures/sig1.xml` part | `.tsr` sidecar |
| **ODF** (`.odt`/`.ods`/`.odp`) | ZIP + `opendocument` manifest | `META-INF/documentsignatures.xml` | `.tsr` sidecar |
| **XML** | `<?xml` / `<` prefix | XAdES enveloped `SignatureTimestamp` | `.tsr` sidecar |
| **Generic** | anything else | `.tsr` sidecar | — |

> **Note on PDF:** Signum writes a structurally valid `DocTimeStamp` with a
> correctly measured `/ByteRange`. For fully PAdES-conformant, cross-tool
> verification, use the `.tsr` sidecar mode (Settings → PDF Mode). Binding the
> token directly to the `/ByteRange` digest is planned.

## Default TSA endpoints

| Role | Endpoint |
|---|---|
| Primary | `http://timestamp.digicert.com` |
| Fallback | `https://rfc3161.ai.moda` |

Both are configurable in **Settings (⌘,)**, along with the hash algorithm
(SHA-256 / SHA-512), per-format embedding mode, and notifications.

## Building

Requires **Xcode 15+** and **macOS 13 (Ventura) or later**.

```bash
git clone https://github.com/di0nx/signum.git
cd signum
open Signum.xcodeproj
```

Xcode resolves the sole Swift Package Manager dependency
([ZIPFoundation](https://github.com/weichsel/ZIPFoundation)) automatically on
first build. Select the **Signum** scheme and run.

The project defines three product targets plus a test bundle:

| Target | Type | Purpose |
|---|---|---|
| `Signum` | App | Main SwiftUI application |
| `SignumKit` | Framework | Shared RFC 3161 / DER / timestamping logic |
| `SignumQuickAction` | Action Extension | Finder Quick Action |
| `SignumKitTests` | Unit tests | DER encoding/parsing & hashing coverage |

Run the tests with **⌘U** (or `xcodebuild test -scheme SignumKit`).

## Configuring a custom TSA

Open **Settings (⌘,)** and set **Primary TSA URL** (and optionally a fallback).
Any RFC 3161-compliant HTTP TSA works. The extension reads the same settings via
the shared App Group `group.net.kitsos.signum`.

## Verifying a timestamp from the CLI

A `.tsr` sidecar is a standard RFC 3161 `TimeStampResp` and can be verified with
OpenSSL:

```bash
# Verify a sidecar token against the original file
openssl ts -verify \
  -in document.pdf.tsr \
  -data document.pdf \
  -CAfile tsa-ca-chain.pem

# Inspect a token
openssl ts -reply -in document.pdf.tsr -text
```

(Supply the TSA's CA chain via `-CAfile`; for DigiCert this is their public
timestamp root/intermediate bundle.)

## Installation & Gatekeeper

Signum is distributed via GitHub Releases as a `.dmg`, signed with the Kitsos
code-signing certificate (no Apple Developer ID). On first launch macOS
Gatekeeper will warn about the developer. To open it:

- **Option A (recommended):** Right-click the app → **Open** → **Open Anyway**.
- **Option B:** `xattr -dr com.apple.quarantine /Applications/Signum.app`
- **Option C:** System Settings → Privacy & Security → **Open Anyway**.

Each release description includes the SHA-256 checksum of the `.dmg`.

## License

MIT — see [LICENSE](LICENSE).
