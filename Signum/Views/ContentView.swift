//
//  ContentView.swift
//  Signum
//

import SwiftUI

/// The root TabView container hosting Stamp, Verify, and History.
struct ContentView: View {
    private enum Tab: Hashable { case stamp, verify, history }
    @State private var selection: Tab = .stamp

    var body: some View {
        TabView(selection: $selection) {
            StampView()
                .tabItem { Label(String(localized: "Stamp"), systemImage: "seal.fill") }
                .tag(Tab.stamp)

            VerifyView()
                .tabItem { Label(String(localized: "Verify"), systemImage: "checkmark.seal") }
                .tag(Tab.verify)

            HistoryView()
                .tabItem { Label(String(localized: "History"), systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .navigation) {
                KitsosLogo()
            }
        }
    }
}

#Preview {
    ContentView()
}
