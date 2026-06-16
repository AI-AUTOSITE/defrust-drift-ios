//
//  RootView.swift
//  Drift
//
//  The three-tab shell (Overview / Subscriptions / Cancel). Holds the
//  deep-link router and switches tabs when a `drift://` URL or a notification
//  tap sets a route. The Liquid Glass tab bar comes for free on iOS 26 just by
//  using TabView; we additionally minimize it on scroll-down there.
//

import SwiftUI

struct RootView: View {
    @State private var router = DriftDeepLinkRouter.shared
    @State private var selection: AppTab = .overview

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
        .modifier(GlassTabBarBehavior())
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
