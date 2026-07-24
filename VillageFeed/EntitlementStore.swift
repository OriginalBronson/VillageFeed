import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class EntitlementStore {
    static let productID = "app.villagefeed.plus.monthly"

    private(set) var product: Product?
    private(set) var hasPlus = false
    // Signed transaction backing the current entitlement. The server re-verifies
    // it (sync-entitlement edge function) before granting is_plus; nil means no
    // active subscription, which tells the server to drop the paid tier.
    private(set) var latestTransactionJWS: String?
    private(set) var lastError: String?
    // Supabase user id while signed in. New purchases carry it as the
    // appAccountToken so the server can tie the receipt to the account.
    var appAccountToken: UUID?
    var debugPlus = false // simulator/testing escape hatch; UI-exposed in DEBUG only

    var isPlus: Bool { hasPlus || debugPlus }

    private var updatesTask: Task<Void, Never>?

    func start() async {
        updatesTask = updatesTask ?? Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refresh()
            }
        }
        await loadProduct()
        await refresh()
    }

    /// Fetches the subscription product; callable again from the paywall's
    /// retry state when the first load failed (plan 01-A2 — the Subscribe
    /// button must never be a silent dead end).
    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            if product != nil { lastError = nil }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() async {
        var owned = false
        var jws: String?
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
                jws = entitlement.jwsRepresentation
            }
        }
        hasPlus = owned
        latestTransactionJWS = jws
    }

    func purchase() async {
        guard let product else { return }
        do {
            var options: Set<Product.PurchaseOption> = []
            if let appAccountToken {
                options.insert(.appAccountToken(appAccountToken))
            }
            let result = try await product.purchase(options: options)
            if case .success(.verified(let transaction)) = result {
                await transaction.finish()
                await refresh()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        try? await StoreKit.AppStore.sync()
        await refresh()
    }
}
