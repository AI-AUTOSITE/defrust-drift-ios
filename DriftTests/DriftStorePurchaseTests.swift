import StoreKit
import StoreKitTest
import Testing
import Foundation
@testable import Drift

// 変更後 — CI 環境ではスキップ(GitHub Actions は CI=true を自動でセット)
@Suite("StoreKit 2 — DriftStore purchase flow", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil,
                "SKTestSession broken on iOS 26.3–26.5 simulators (FB22237318); local-only until Apple fixes it"))
@MainActor
struct DriftStorePurchaseTests {

    let session: SKTestSession
    let store: DriftStore

    init() throws {
        let session = try SKTestSession(configurationFileNamed: "Drift")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        self.session = session
        self.store = DriftStore()
    }

    @Test("Fresh state — isPro is false")
    func freshIsNotPro() async {
        await store.updateEntitlements()
        #expect(store.isPro == false)
    }

    @Test("Purchase lifetime → isPro becomes true")
    func purchaseUnlocksPro() async throws {
        _ = try await session.buyProduct(identifier: "com.defrust.drift.pro.lifetime")
        await store.updateEntitlements()
        #expect(store.isPro == true)
    }

    @Test("Refund revokes Pro")
        func refundRevokesPro() async throws {
            let transaction = try await session.buyProduct(identifier: "com.defrust.drift.pro.lifetime")
            await store.updateEntitlements()
            #expect(store.isPro == true)   // 購入直後は Pro になっているはず

            try session.refundTransaction(identifier: UInt(transaction.id))
            // 返金が currentEntitlements に伝播するのを少し待つ
            try await Task.sleep(for: .milliseconds(500))
            await store.updateEntitlements()
            #expect(store.isPro == false)
        }

    @Test("Restore brings back Pro after a fresh install")
    func restoreFromExistingPurchase() async throws {
        _ = try await session.buyProduct(identifier: "com.defrust.drift.pro.lifetime")
        // A new store instance == a fresh install reading current entitlements.
        let freshStore = DriftStore()
        await freshStore.updateEntitlements()
        #expect(freshStore.isPro == true)
    }
}
