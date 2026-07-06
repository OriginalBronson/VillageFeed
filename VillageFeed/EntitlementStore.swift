import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class EntitlementStore {
    static let productID = "app.villagefeed.plus.monthly"

    private(set) var product: Product?
    private(set) var hasPlus = false
    private(set) var lastError: String?
    var debugPlus = false // simulator/testing escape hatch; UI-exposed in DEBUG only

    var isPlus: Bool { hasPlus || debugPlus }

    private var updatesTask: Task<Void, Never>?

    func start() async {
        updatesTask = updatesTask ?? Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refresh()
            }
        }
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    func refresh() async {
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        hasPlus = owned
    }

    func purchase() async {
        guard let product else { return }
        do {
            let result = try await product.purchase()
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
