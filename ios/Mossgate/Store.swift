import StoreKit
import SwiftUI

/// The one in-app purchase: everything past the free world.
///
/// `SettingsStore.hasFullGame` is the single source of truth for the paywall — this
/// type only ever writes it, from StoreKit's own entitlement records rather than
/// from what the purchase call happened to return. That matters on a reinstall:
/// `currentEntitlements` is what survives, not the result of a transaction that
/// happened on another device.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    /// Matches the product id published in the support page's privacy policy.
    static let productID = "com.jphsystems.mossgate.fullgame"

    @Published private(set) var product: Product?
    @Published private(set) var busy = false
    /// Last thing worth telling the player, shown as an alert.
    @Published var message: String?

    private var updates: Task<Void, Never>?

    private init() {}

    /// Formatted price from the App Store, or nil when it cannot be reached.
    var priceText: String? { product?.displayPrice }

    func start() {
        // Test hook: -UnlockFullGame 1 grants the paid set without a purchase, so
        // the five locked worlds can be played and photographed in the simulator,
        // where there is no App Store account and no product to buy.
        if ProcessInfo.processInfo.arguments.contains("-UnlockFullGame") {
            SettingsStore.shared.hasFullGame = true
        }
        // Purchases can complete outside the app (Ask to Buy, another device), so
        // the entitlement is watched rather than only checked on tap.
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update, t.productID == Self.productID {
                    SettingsStore.shared.hasFullGame = true
                    await t.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    private func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            product = nil
        }
    }

    /// The authoritative check: what Apple says this Apple ID owns right now.
    func refreshEntitlements() async {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, t.productID == Self.productID {
                SettingsStore.shared.hasFullGame = true
                return
            }
        }
    }

    func buy() async {
        guard let product else {
            message = "The App Store isn't reachable right now. Check your connection and try again."
            return
        }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    SettingsStore.shared.hasFullGame = true
                    await t.finish()
                } else {
                    message = "The App Store couldn't verify that purchase."
                }
            case .pending:
                message = "Waiting for the App Store to approve this purchase."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !SettingsStore.shared.hasFullGame {
                message = "No previous purchase was found for this Apple ID."
            }
        } catch {
            message = "Couldn't reach the App Store to restore."
        }
    }
}
