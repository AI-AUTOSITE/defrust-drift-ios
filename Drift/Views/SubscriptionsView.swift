//
//  SubscriptionsView.swift
//  Drift
//
//  Lists the user's subscriptions. Adding, editing, swipe-to-delete and the
//  detail screen arrive in the next step; for now this shows the list (with an
//  empty state) so the tab is wired and the tokens are exercised end-to-end.
//

import SwiftData
import SwiftUI

private typealias Subscription = DriftSchemaV1.Subscription

struct SubscriptionsView: View {
    @Query(sort: \Subscription.name)
    private var subscriptions: [Subscription]

    var body: some View {
        NavigationStack {
            Group {
                if subscriptions.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions",
                        systemImage: "creditcard",
                        description: Text("Subscriptions you add will appear here.")
                    )
                } else {
                    List(subscriptions, id: \.persistentModelID) { subscription in
                        SubscriptionRow(subscription: subscription)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Subscriptions")
        }
    }
}

private struct SubscriptionRow: View {
    let subscription: Subscription

    var body: some View {
        HStack(spacing: DriftSpacing.s12) {
            Image(systemName: subscription.iconName)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(hex: subscription.customColor))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.body)
                Text("Renews \(subscription.nextRenewalDate.formatted(.dateTime.month().day()))")
                    .font(.footnote)
                    .foregroundStyle(DriftTheme.subtleText)
            }

            Spacer(minLength: DriftSpacing.s8)

            Text(subscription.monthlyCost,
                 format: .currency(code: subscription.currencyCode))
                .font(DriftTypography.amount)
        }
        .padding(.vertical, DriftSpacing.s4)
    }
}
