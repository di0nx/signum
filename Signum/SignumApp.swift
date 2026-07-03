//
//  SignumApp.swift
//  Signum
//
//  RFC 3161 timestamping for macOS — part of the Kitsos ecosystem.
//

import SwiftUI
import UserNotifications

@main
struct SignumApp: App {
    @Environment(\.colorScheme) private var colorScheme

    init() {
        // Request notification authorization up front; result handled silently.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 480)
                .tint(.kitsosPrimary)
                .accentColor(.kitsosPrimary)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "About Signum")) {
                    AboutWindow.show()
                }
            }
        }

        Settings {
            SettingsView()
                .tint(.kitsosPrimary)
        }
    }
}
