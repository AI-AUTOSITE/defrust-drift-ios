import Foundation
import Observation
import StoreKit
import UIKit

/// StoreKit 2 wrapper for Drift's single non-consumable Pro upgrade.
///
/// Design (drift-part-1a-core-schema.md §4):
/// - One product: `com.defrust.drift.pro.lifetime` ($14.99, Family Sharing ON).
/// - `Transaction.updates` is listened to from launch so out-of-app grants
///   (Family Sharing, Ask to Buy approval, renewals) are never missed.
/// - `AppStore.sync()` is called ONLY behind the Restore button (it prompts for
///   an Apple ID password, so calling it on launch breaks UX).
/// - No server, so JWS is never re-verified remotely; entitlement state is
///   event-driven (`Transaction.updates` + a foreground refresh).
@Observable
@MainActor
final class DriftStore {

    // MARK: - State
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoadingProducts: Bool = false
    private(set) var lastError: String?

    private let productIDs = ["com.defrust.drift.pro.lifetime"]

    var isPro: Bool {
        purchasedProductIDs.contains("com.defrust.drift.pro.lifetime")
    }

    /// Free tier's maximum subscription count.
    static let freeTierLimit: Int = 5

    private var transactionListener: Task<Void, Never>?

    // MARK: - Init
    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updateEntitlements()
        }
    }

    // MARK: - Product loading
    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            self.products = try await Product.products(for: productIDs)
        } catch {
            lastError = "Failed to load products: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateEntitlements()
            await transaction.finish()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Restore (manual)
    /// ⚠️ Prompts for the Apple ID password, so only ever call this from an
    /// explicit button. Calling it on launch breaks UX.
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateEntitlements()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlement update
    func updateEntitlements() async {
        var verified: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                verified.insert(transaction.productID)
            }
        }
        self.purchasedProductIDs = verified
    }

    // MARK: - Transaction listener (Family Sharing, renewals, etc.)
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await self.updateEntitlements()
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Verification helper
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Refresh on foreground
    func refreshOnForeground() async {
        await updateEntitlements()
    }

    // MARK: - Refund (Settings → Request Refund)
    func requestRefund() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        do {
            guard case .verified(let transaction) = await Transaction.latest(for: "com.defrust.drift.pro.lifetime") else {
                lastError = "No purchase found to refund."
                return
            }
            let status = try await transaction.beginRefundRequest(in: scene)
            switch status {
            case .success: break
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            lastError = "Refund request failed: \(error.localizedDescription)"
        }
    }
}
