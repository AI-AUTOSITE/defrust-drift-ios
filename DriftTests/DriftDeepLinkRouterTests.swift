@testable import Drift
import Foundation
import Testing

// The router is a @MainActor singleton, so the suite is serialized: tests share
// `DriftDeepLinkRouter.shared` and each resets `route` before asserting.
@MainActor
@Suite("DriftDeepLinkRouter", .serialized)
struct DriftDeepLinkRouterTests {

    private var router: DriftDeepLinkRouter { DriftDeepLinkRouter.shared }

    @Test("subscription URL parses into a subscription route")
    func subscriptionURL() {
        let id = UUID()
        router.route = nil
        let matched = router.handle(url: URL(string: "drift://subscription/\(id.uuidString)")!)
        #expect(matched)
        #expect(router.route == .subscription(id))
    }

    @Test("overview URL parses into the overview route")
    func overviewURL() {
        router.route = nil
        let matched = router.handle(url: URL(string: "drift://overview")!)
        #expect(matched)
        #expect(router.route == .overview)
    }

    @Test("open(subscriptionID:) sets a subscription route")
    func openSetsRoute() {
        let id = UUID()
        router.route = nil
        router.open(subscriptionID: id)
        #expect(router.route == .subscription(id))
    }

    @Test("non-drift scheme is ignored and leaves the route unchanged")
    func wrongSchemeIgnored() {
        router.route = nil
        let matched = router.handle(url: URL(string: "https://example.com/subscription/x")!)
        #expect(!matched)
        #expect(router.route == nil)
    }

    @Test("malformed subscription UUID is rejected")
    func malformedUUID() {
        router.route = nil
        let matched = router.handle(url: URL(string: "drift://subscription/not-a-uuid")!)
        #expect(!matched)
        #expect(router.route == nil)
    }

    @Test("unknown host is rejected")
    func unknownHost() {
        router.route = nil
        let matched = router.handle(url: URL(string: "drift://settings")!)
        #expect(!matched)
        #expect(router.route == nil)
    }
}
