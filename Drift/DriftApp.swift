//
//  DriftApp.swift
//  Drift
//
//  App entry point. Wires the pieces of "engine" built on Days 1–5 into the
//  running app: the shared SwiftData container, the notification action
//  handler, the Siri/Shortcuts provider, and the StoreKit wrapper. Navigation
//  lives in RootView.
//

import AppIntents
import SwiftData
import SwiftUI

@main
struct DriftApp: App {
    /// The single StoreKit wrapper, created once at launch so `Transaction.updates`
    /// is observed for the whole session (Family Sharing grants, Ask to Buy
    /// approvals, renewals) and shared into the environment. Settings reads
    /// `isPro` and triggers Restore / Refund through it; the paywall will too.
    @State private var store = DriftStore()

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
        .environment(store)
    }
}
