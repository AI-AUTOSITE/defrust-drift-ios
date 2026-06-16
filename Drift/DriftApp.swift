//
//  DriftApp.swift
//  Drift
//
//  App entry point. Wires the three pieces of "engine" built on Days 1–5 into
//  the running app: the shared SwiftData container, the notification action
//  handler, and the Siri/Shortcuts provider. Navigation lives in RootView.
//

import AppIntents
import SwiftData
import SwiftUI

@main
struct DriftApp: App {
    init() {
        // Let notification actions (Mark used / Snooze) reach SwiftData without a view.
        NotificationActionHandler.shared.configure(container: SharedModelContainer.shared)
        // Register the App Shortcuts (Monthly spend, Add, Mark used, Run review).
        DriftAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(SharedModelContainer.shared)
    }
}
