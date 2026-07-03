import Foundation

/// Where a subscription is billed — the platform/account that actually charges
/// the user. Cancellation location depends on this, NOT on the service itself
/// (a service like Max can be billed via Apple, Amazon, Roku, or direct, and
/// each is cancelled in a completely different place).
///
/// Stored as a raw `String` on `Subscription.billingChannelRaw` so adding cases
/// later never needs a SwiftData migration — mirrors `BillingCycle`.
///
/// IMPORTANT: raw values are persisted in the store (and synced via CloudKit),
/// so **never change an existing raw value once shipped**. Display names are
/// safe to change; raw values are not.
///
/// (Design: docs/cancellation-billing-channel-design.md)
enum BillingChannel: String, Codable, CaseIterable, Identifiable {
    // Declaration order = the order shown in the "Where did you subscribe?" picker.
    case appleAppStore      = "apple_app_store"
    case googlePlay         = "google_play"
    case amazonSubscriptions = "amazon_subscriptions"
    case amazonChannels     = "amazon_channels"
    case amazonSubscribeSave = "amazon_subscribe_save"
    case amazonAppstore     = "amazon_appstore"
    case paypal             = "paypal"
    case roku               = "roku"
    case microsoft          = "microsoft"
    case xbox               = "xbox"
    case playStation        = "playstation"
    case samsung            = "samsung"
    case carrierATT         = "carrier_att"
    case carrierOther       = "carrier_other"
    case directWeb          = "direct_web"
    case unknown            = "unknown"

    var id: String { rawValue }

    // MARK: - Per-channel data (single source of truth)

    /// All display data for a channel, built once in `info` so there is one
    /// switch to maintain rather than one per property.
    struct Info {
        let displayName: String
        /// Canonical management URL / deep link, or `nil` when the channel has
        /// no stable link and the user must follow the manual steps.
        let managementURLString: String?
        /// Short manual steps (used when there is no deep link, or as a fallback).
        let steps: [String]
        /// The one gotcha specific to THIS channel (universal ones live in
        /// `universalGotchas`). `nil` when there is nothing channel-specific.
        let gotcha: String?
        /// What the biller typically looks like on a bank/card statement — used
        /// by the "not sure where you subscribed?" cheat sheet.
        let statementHint: String?
        /// True for app-store-style billing where "deleting the app ≠ cancel"
        /// applies (Apple, Google, Amazon Appstore, Samsung).
        let isAppStoreBilled: Bool
        /// yyyy-MM-dd. When these steps/links were last checked against the live
        /// platform. NEEDS live re-verification before shipping.
        let lastVerified: String
    }

    var info: Info {
        switch self {
        case .appleAppStore:
            return Info(
                displayName: "Apple (App Store)",
                managementURLString: "itms-apps://apps.apple.com/account/subscriptions",
                steps: [
                    "Open Settings and tap your name at the top.",
                    "Tap Subscriptions.",
                    "Tap this subscription, then Cancel Subscription (scroll if needed)."
                ],
                gotcha: "Deleting the app does NOT cancel it — an App Store subscription keeps renewing until you cancel here.",
                statementHint: "APPLE.COM/BILL",
                isAppStoreBilled: true,
                lastVerified: "2026-06-29"
            )
        case .googlePlay:
            return Info(
                displayName: "Google Play",
                managementURLString: "https://play.google.com/store/account/subscriptions",
                steps: [
                    "Open the Play Store and tap your profile icon.",
                    "Tap Payments & subscriptions → Subscriptions.",
                    "Pick this subscription and tap Cancel subscription."
                ],
                gotcha: "Uninstalling the app does NOT cancel it. If you can't find it, check you're signed into the right Google account.",
                statementHint: "GOOGLE *",
                isAppStoreBilled: true,
                lastVerified: "2026-06-29"
            )
        case .amazonSubscriptions:
            return Info(
                displayName: "Amazon (subscription)",
                managementURLString: "https://www.amazon.com/yourmembershipsandsubscriptions",
                steps: [
                    "Go to Amazon → Account → Memberships & Subscriptions.",
                    "Find this subscription and open Manage Subscription.",
                    "Turn off auto-renew or Cancel Subscription."
                ],
                gotcha: "Cancelling Prime does not cancel services you added through Amazon — cancel those separately.",
                statementHint: "AMZN / Amazon",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .amazonChannels:
            return Info(
                displayName: "Amazon (Prime Video Channel)",
                managementURLString: "https://www.amazon.com/yourmembershipsandsubscriptions",
                steps: [
                    "Go to Amazon → Account → Memberships & Subscriptions (or Prime Video → Channels).",
                    "Find the channel under your Prime Video Channels.",
                    "Tap Cancel Channel and confirm."
                ],
                gotcha: "A service added through Amazon (Prime Video Channels) can't be cancelled on the service's own website — only through Amazon.",
                statementHint: "AMZN / Amazon",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .amazonSubscribeSave:
            return Info(
                displayName: "Amazon Subscribe & Save",
                managementURLString: nil,
                steps: [
                    "Go to Amazon → Account → Subscribe & Save.",
                    "Open the Subscriptions tab and pick the item.",
                    "Choose Cancel my subscription and select a reason."
                ],
                gotcha: "Cancel before the 'last day to update' date shown on the order, or the next box still ships.",
                statementHint: "AMZN / Amazon",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .amazonAppstore:
            return Info(
                displayName: "Amazon Appstore (Fire)",
                managementURLString: nil,
                steps: [
                    "Go to Amazon → Your Account → Your Apps → Your Subscriptions (or on Fire: Apps → Store → Manage Subscriptions).",
                    "Find this subscription.",
                    "Turn off auto-renewal."
                ],
                gotcha: "Uninstalling the app does NOT stop billing — turn off auto-renewal.",
                statementHint: "AMZN / Amazon",
                isAppStoreBilled: true,
                lastVerified: "2026-06-29"
            )
        case .paypal:
            return Info(
                displayName: "PayPal",
                managementURLString: nil,
                steps: [
                    "Open PayPal → Settings (gear) → Payments.",
                    "Tap Manage automatic payments.",
                    "Select this merchant and tap Cancel."
                ],
                gotcha: "Cancelling here stops the PayPal charge but may not end the service itself — also cancel with the service directly.",
                statementHint: "PAYPAL *",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .roku:
            return Info(
                displayName: "Roku",
                managementURLString: "https://my.roku.com/subscriptions",
                steps: [
                    "Go to my.roku.com → Manage subscriptions (or on the device: highlight the channel, press ✱).",
                    "Select this subscription.",
                    "Turn off auto-renew."
                ],
                gotcha: "Some services Roku bills (e.g. Disney+, Hulu) are still cancelled on the service, not Roku — check where the subscription is listed.",
                statementHint: "Roku / Roku for …",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .microsoft:
            return Info(
                displayName: "Microsoft account",
                managementURLString: "https://account.microsoft.com/services",
                steps: [
                    "Go to account.microsoft.com/services and sign in.",
                    "Find this subscription under Services & subscriptions.",
                    "Tap Manage → Cancel."
                ],
                gotcha: "If you bought it via Apple, Google, or a retailer, cancel there instead — not in your Microsoft account.",
                statementHint: "MICROSOFT / MSFT",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .xbox:
            return Info(
                displayName: "Xbox (Microsoft)",
                managementURLString: "https://account.microsoft.com/services",
                steps: [
                    "Go to account.microsoft.com/services (or on console: Profile & system → Settings → Account → Subscriptions).",
                    "Find Game Pass / this subscription.",
                    "Tap Manage → Cancel."
                ],
                gotcha: "Game Pass bought via a promo or third party may need to be cancelled with that provider.",
                statementHint: "MICROSOFT / XBOX",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .playStation:
            return Info(
                displayName: "PlayStation",
                managementURLString: nil,
                steps: [
                    "Go to PlayStation Account Management → Subscriptions (or on PS5: Settings → Users and Accounts → Account → Payment and Subscriptions → Subscriptions).",
                    "Select this subscription.",
                    "Tap Cancel Subscription / turn off auto-renew."
                ],
                gotcha: "Access continues to the next payment date; there's a limited refund window via PlayStation Support.",
                statementHint: "PlayStation / SONY",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .samsung:
            return Info(
                displayName: "Samsung (Galaxy Store)",
                managementURLString: nil,
                steps: [
                    "Open Galaxy Store → Menu → Subscriptions.",
                    "Select this app.",
                    "Tap Unsubscribe."
                ],
                gotcha: "You must be signed into the same Samsung account you purchased with.",
                statementHint: "Samsung",
                isAppStoreBilled: true,
                lastVerified: "2026-06-29"
            )
        case .carrierATT:
            return Info(
                displayName: "Phone bill (AT&T)",
                managementURLString: "https://www.att.com/db",
                steps: [
                    "Go to att.com/db (Mobile Purchases) and enter your wireless number.",
                    "Enter the one-time PIN texted to you.",
                    "Find this subscription and cancel it (or use AT&T Purchase Blocker)."
                ],
                gotcha: "Charges on your phone bill don't appear in Apple/Google subscription lists.",
                statementHint: "On your AT&T phone bill",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .carrierOther:
            return Info(
                displayName: "Phone bill (other carrier)",
                managementURLString: nil,
                steps: [
                    "Check your phone bill for the charge.",
                    "Sign into your carrier's account, or contact the carrier.",
                    "Ask them to stop the third-party subscription / content charge."
                ],
                gotcha: "Charges billed to your phone bill are cancelled through your carrier, not the app store.",
                statementHint: "On your phone bill",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .directWeb:
            return Info(
                displayName: "The service directly",
                managementURLString: nil,   // handled by the service's own guide via the router
                steps: [
                    "Sign into the service's own website or app.",
                    "Open Account / Settings → Subscription or Membership.",
                    "Cancel there (this is the only channel you cancel on the service's own site)."
                ],
                gotcha: nil,
                statementHint: "The service's own name",
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        case .unknown:
            return Info(
                displayName: "Not sure",
                managementURLString: nil,
                steps: [
                    "Check your bank/card statement for the biller name.",
                    "Match it to a payment method (Apple, Google, Amazon, Roku, PayPal, your phone bill…).",
                    "Then follow that channel's steps."
                ],
                gotcha: nil,
                statementHint: nil,
                isAppStoreBilled: false,
                lastVerified: "2026-06-29"
            )
        }
    }

    // MARK: - Convenience accessors

    var displayName: String { info.displayName }
    var steps: [String] { info.steps }
    var gotcha: String? { info.gotcha }
    var statementHint: String? { info.statementHint }
    var isAppStoreBilled: Bool { info.isAppStoreBilled }
    var lastVerified: String { info.lastVerified }

    /// Parsed management URL, or `nil` when the channel has no stable link.
    var managementURL: URL? {
        guard let string = info.managementURLString else { return nil }
        return URL(string: string)
    }

    /// Channels offered in the "Where did you subscribe?" picker (everything
    /// except `.unknown`, which is the implicit default when nothing is chosen).
    static var selectableChannels: [Self] {
        allCases.filter { $0 != .unknown }
    }

    // MARK: - Universal gotchas (shown on every channel guide)

    static let universalGotchas: [String] = [
        "Deleting an app never cancels a subscription billed through a platform — it keeps renewing until you cancel.",
        "If you subscribed THROUGH a platform (Apple, Google, Amazon, Roku), you usually can't cancel on the service's own website — cancel through that platform.",
        "Cancelling usually takes effect at the end of the current billing period. You keep access until then, and there's normally no refund for the unused time.",
        "On a free trial, cancel before it ends to avoid being charged (Apple: at least 24 hours before it renews)."
    ]
}
