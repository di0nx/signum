//
//  ActionViewController.swift
//  SignumQuickAction
//
//  The Finder Quick Action panel. Receives file URLs from the extension
//  context, offers "Add Timestamp" / "Verify Timestamp", and shows a brief
//  status. TSA settings are read from the shared App Group defaults.
//

import Cocoa
import UniformTypeIdentifiers
import SignumKit

final class ActionViewController: NSViewController {

    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let stampButton = NSButton(title: NSLocalizedString("Add Timestamp", comment: ""), target: nil, action: nil)
    private let verifyButton = NSButton(title: NSLocalizedString("Verify Timestamp", comment: ""), target: nil, action: nil)

    private var fileURLs: [URL] = []
    private let coordinator = TimestampCoordinator()

    override func loadView() {
        // Programmatic view so no storyboard outlets are required.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 160))

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.maximumNumberOfLines = 3
        statusLabel.stringValue = NSLocalizedString("Ready", comment: "")

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        spinner.controlSize = .small

        stampButton.translatesAutoresizingMaskIntoConstraints = false
        stampButton.bezelStyle = .rounded
        stampButton.keyEquivalent = "\r"
        stampButton.target = self
        stampButton.action = #selector(didTapStamp)

        verifyButton.translatesAutoresizingMaskIntoConstraints = false
        verifyButton.bezelStyle = .rounded
        verifyButton.target = self
        verifyButton.action = #selector(didTapVerify)

        let buttons = NSStackView(views: [stampButton, verifyButton])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.orientation = .horizontal
        buttons.spacing = 12

        container.addSubview(statusLabel)
        container.addSubview(spinner)
        container.addSubview(buttons)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),

            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),

            buttons.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            buttons.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20)
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        fileURLs = extractFileURLs()
        if fileURLs.isEmpty {
            statusLabel.stringValue = NSLocalizedString("No files provided", comment: "")
            stampButton.isEnabled = false
            verifyButton.isEnabled = false
        } else {
            statusLabel.stringValue = String(format: NSLocalizedString("%d file(s) ready", comment: ""), fileURLs.count)
        }
    }

    // MARK: - Actions

    @objc private func didTapStamp() {
        run { [coordinator] url in
            let result = try await coordinator.stamp(fileURL: url)
            return String(format: NSLocalizedString("✓ %@ via %@", comment: ""), result.fileName, result.tsaName)
        }
    }

    @objc private func didTapVerify() {
        run { [coordinator] url in
            let result = try await coordinator.verify(fileURL: url)
            let mark = result.isValid ? "✅" : "❌"
            let name = result.tsaName ?? NSLocalizedString("Unknown TSA", comment: "")
            return "\(mark) \(url.lastPathComponent) — \(name)"
        }
    }

    private func run(_ operation: @escaping (URL) async throws -> String) {
        setBusy(true)
        let urls = fileURLs
        Task { @MainActor in
            var messages: [String] = []
            for url in urls {
                do {
                    messages.append(try await operation(url))
                } catch {
                    messages.append("⚠️ \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            statusLabel.stringValue = messages.joined(separator: "\n")
            setBusy(false)
        }
    }

    private func setBusy(_ busy: Bool) {
        stampButton.isEnabled = !busy && !fileURLs.isEmpty
        verifyButton.isEnabled = !busy && !fileURLs.isEmpty
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    // MARK: - Input extraction

    private func extractFileURLs() -> [URL] {
        var urls: [URL] = []
        for item in extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let semaphore = DispatchSemaphore(value: 0)
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    if let url = data as? URL {
                        urls.append(url)
                    } else if let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 2)
            }
        }
        return urls
    }

    // MARK: - Completion

    @IBAction func done(_ sender: AnyObject?) {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
