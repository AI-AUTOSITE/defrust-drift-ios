import Foundation
import Observation

/// Central sink for "navigate to X" requests coming from notification taps, widget deep
/// links (`drift://...`), and (later) Spotlight. The app observes ``route`` and drives its
/// `NavigationStack`; setting `route` is the only side effect here.
///
/// Uses `@Observable` to match `DriftStore`. When the app shell is built, hold it via
/// `@State private var router = DriftDeepLinkRouter.shared` (or inject through the
/// environment) and react to `router.route` changes.
@MainActor
@Observable
public final class DriftDeepLinkRouter {
    public static let shared = DriftDeepLinkRouter()

    public enum Route: Equatable, Hashable {
        case subscription(UUID)
        case overview
    }

    public var route: Route?

    private init() {}

    /// Notification default-action tap → open that subscription's detail.
    public func open(subscriptionID: UUID) {
        route = .subscription(subscriptionID)
    }

    /// Parse a `drift://` URL. Handles `drift://subscription/<uuid>` (notification default
    /// action / future links) and `drift://overview` (widget tap). Returns whether the URL
    /// matched a known route, so the caller can fall through for anything else.
    @discardableResult
    public func handle(url: URL) -> Bool {
        guard url.scheme == "drift" else { return false }
        switch url.host {
        case "subscription":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return false }
            route = .subscription(id)
            return true
        case "overview":
            route = .overview
            return true
        default:
            return false
        }
    }
}
