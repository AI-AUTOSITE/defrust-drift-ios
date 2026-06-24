//
//  RootView.swift
//  Drift
//
//  The three-tab shell (Overview / Subscriptions / Cancel). Holds the
//  deep-link router and switches tabs when a `drift://` URL or a notification
//  tap sets a route. The Liquid Glass tab bar comes for free on iOS 26 just by
//  using TabView; we additionally minimize it on scroll-down there.
//
//  On first appearance it seeds the ten default categories so the Add form has
//  something to pick from on a fresh install. `seedIfNeeded` is idempotent
//  (it no-ops once any category exists), so calling it on appear is safe.
//
//  On first launch it presents the onboarding flow as a full-screen cover,
//  gated by `@AppStorage("hasCompletedOnboarding")` so it is shown exactly once.
//

import Observation
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var router = DriftDeepLinkRouter.shared
    @State private var selection: AppTab = .overview
    @State private var deletionState = DeletionState()

    var body: some View {
        TabView(selection: $selection) {
            OverviewView()
                .tabItem { Label("Overview", systemImage: "chart.pie") }
                .tag(AppTab.overview)

            SubscriptionsView()
                .tabItem { Label("Subscriptions", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.subscriptions)

            CancelGuidesView()
                .tabItem { Label("Cancel", systemImage: "scissors") }
                .tag(AppTab.cancel)
        }
        .tint(DriftTheme.accent)
        .environment(deletionState)
        .modifier(GlassTabBarBehavior())
        .onAppear { Category.seedIfNeeded(in: context) }
        .task { await NotificationScheduler.shared.reconcileCancelReminders() }
        .onOpenURL { router.handle(url: $0) }
        .onChange(of: router.route) { _, route in
            switch route {
            case .some(.overview):
                selection = .overview
            case .some(.subscription):
                // Pushing the detail screen arrives with the subscription
                // detail view; for now we surface the Subscriptions tab.
                selection = .subscriptions
            case .none:
                break
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingView { hasCompletedOnboarding = true }
        }
    }
}

enum AppTab: Hashable {
    case overview
    case subscriptions
    case cancel
}

/// iOS 26 Liquid Glass nicety: minimize the tab bar when scrolling down.
/// No-op on iOS 17–18 (the tab bar is still standard there).
private struct GlassTabBarBehavior: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

/// Tracks the subscription currently in its swipe-delete undo window. Shared
/// across tabs so the Overview total can drop it immediately and restore it on
/// undo, staying in sync with the Subscriptions list (the delete itself is only
/// committed once the window elapses).
@Observable
final class DeletionState {
    var pendingID: PersistentIdentifier?
}
