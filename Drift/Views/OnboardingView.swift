//
//  OnboardingView.swift
//  Drift
//
//  First-launch onboarding (four screens, horizontal paging). Communicates the
//  local-first / privacy / one-time-purchase value in ~30 seconds. Per the
//  anti-dark-pattern rule (Part 2 §10.7), a Skip button is always present at the
//  top-right so the user is never trapped, and the paywall is NEVER forced here
//  — screen 4 simply states the deal and lets the user start (or restore).
//
//  Completion is persisted by the presenter (RootView) via
//  @AppStorage("hasCompletedOnboarding"); this view just calls `onFinish`.
//
//  Screen 4's Pro copy lists ONLY what actually ships in v1.0 (unlimited
//  subscriptions + reminders), matching PaywallView.proFeatures. iCloud sync and
//  the widgets are free, so they're framed as part of the free tier — not Pro.
//

import SwiftUI

struct OnboardingView: View {
    /// Invoked when the user finishes or skips. RootView sets
    /// `hasCompletedOnboarding`, which dismisses the cover.
    let onFinish: () -> Void

    @Environment(DriftStore.self) private var store
    @State private var selection = 0
    @State private var isRestoring = false

    private let pages: [Page] = [
        Page(
            id: 0,
            symbol: "drop.fill",
            title: "Subscriptions, anchored.",
            message: "Drift gathers your subscriptions in one calm place — no ads, no tracking, no surprises."
        ),
        Page(
            id: 1,
            symbol: "lock.shield.fill",
            title: "Your data stays on your device.",
            message: "Drift uses iCloud only for your own sync, between your own devices. We never see it."
        ),
        Page(
            id: 2,
            symbol: "scissors",
            title: "When you want to cancel, we help — not them.",
            message: "Drift includes step-by-step cancel guides, scored 1–10 by how hard the company "
                + "makes it. We won't make you jump through hoops."
        ),
        Page(
            id: 3,
            symbol: "sparkles",
            title: "Free to use. Pro is $14.99 once.",
            message: "Track subscriptions, sync via your own iCloud, and use the widgets — all free. "
                + "Pro unlocks unlimited subscriptions and renewal reminders, for a single payment."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            skipBar
            TabView(selection: $selection) {
                ForEach(pages) { page in
                    pageView(page).tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            footer
        }
        .tint(DriftTheme.accent)
    }

    // MARK: - Skip (always visible, top-right)

    private var skipBar: some View {
            HStack {
                Spacer()
                Button("Skip") { onFinish() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DriftTheme.accentDeep)
                    .padding(.horizontal, DriftSpacing.s16)
                    .padding(.vertical, DriftSpacing.s8)
                    .background(
                        Capsule().fill(DriftTheme.accentTinted)
                    )
            }
            .padding(.horizontal, DriftSpacing.s20)
            .padding(.top, DriftSpacing.s12)
        }

    // MARK: - Page

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: DriftSpacing.s24) {
            Spacer()
            Image(systemName: page.symbol)
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DriftTheme.accent)
            VStack(spacing: DriftSpacing.s12) {
                Text(page.title)
                    .font(DriftTypography.display)
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(DriftTheme.subtleText)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, DriftSpacing.s32)
    }

    // MARK: - Footer (CTA + restore on the last page)

    private var footer: some View {
        VStack(spacing: DriftSpacing.s16) {
            if selection < pages.count - 1 {
                Button {
                    withAnimation { selection += 1 }
                } label: {
                    Text("Next").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DriftTheme.accent)
            } else {
                Button {
                    onFinish()
                } label: {
                    Text("Start using Drift").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DriftTheme.accent)

                Button("Restore Purchases") { restore() }
                    .font(.footnote)
                    .foregroundStyle(DriftTheme.subtleText)
                    .disabled(isRestoring)
            }
        }
        .padding(.horizontal, DriftSpacing.s24)
        .padding(.bottom, DriftSpacing.s32)
        .animation(.default, value: selection)
    }

    private func restore() {
        isRestoring = true
        Task { @MainActor in
            await store.restorePurchases()
            isRestoring = false
            // If a prior purchase was restored the user is set; let them in.
            if store.isPro { onFinish() }
        }
    }

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let message: String
    }
}
