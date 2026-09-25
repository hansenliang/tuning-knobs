import Foundation
import Observation
import StoreKit

/// StoreKit 2: one auto-renewable tier (C2). The gateway is the source of truth for `plan`.
/// We forward each verified transaction's JWS to `POST /v1/entitlements/apple` and finish
/// the transaction only after the server accepts it.
@MainActor @Observable
final class Store {
    static let proProductID = "app.watchgpt.pro.monthly"

    private(set) var product: Product?
    private(set) var isEligibleForTrial = false
    private(set) var isPurchasing = false
    private(set) var errorMessage: String?

    /// The server confirmed a plan change.
    @ObservationIgnored var onEntitlement: ((EntitlementResponse) -> Void)?

    private let api: APIClient
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    /// Call once at launch (after consent). Starts the `Transaction.updates` listener.
    func start() {
        guard updatesTask == nil else { return }
        // Renewals, Ask to Buy approvals, refunds and purchases made elsewhere all arrive here.
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.process(result)
            }
        }
        Task {
            await loadProduct()
            // Anything the server never acknowledged (e.g. we went offline mid-purchase).
            for await result in Transaction.unfinished {
                await process(result)
            }
        }
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.proProductID]).first
            if let subscription = product?.subscription {
                let hasFreeTrial = subscription.introductoryOffer?.paymentMode == .freeTrial
                isEligibleForTrial = hasFreeTrial ? await subscription.isEligibleForIntroOffer : false
            }
            if product == nil { errorMessage = "Subscription unavailable." }
        } catch {
            Log.store.error("Product load failed: \(error.localizedDescription)")
            errorMessage = "Couldn't reach the App Store."
        }
    }

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await process(verification)
            case .pending:
                errorMessage = "Waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            Log.store.error("Purchase failed: \(error.localizedDescription)")
            errorMessage = "Purchase failed. Try again."
        }
    }

    /// "Restore purchases" (required by App Review for subscriptions).
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "Couldn't reach the App Store."
            return
        }
        for await result in Transaction.currentEntitlements {
            await process(result, finish: false)
        }
    }

    /// The trial line on C2, e.g. "7-day free trial · cancel anytime".
    var trialLine: String {
        guard isEligibleForTrial, let period = product?.subscription?.introductoryOffer?.period else {
            return "Cancel anytime"
        }
        return "\(Self.describe(period)) free trial · cancel anytime"
    }

    private func process(_ result: VerificationResult<Transaction>, finish: Bool = true) async {
        // Forward only what StoreKit verified on-device. The server re-verifies the JWS
        // against Apple's root CA and binds originalTransactionId to this device account.
        guard case .verified(let transaction) = result, transaction.productID == Self.proProductID else { return }
        do {
            let response = try await api.submitAppleTransaction(jws: result.jwsRepresentation)
            onEntitlement?(response)
            if finish { await transaction.finish() }
        } catch {
            // Leave it unfinished: `Transaction.unfinished` hands it back next launch.
            Log.store.error("Entitlement submit failed: \(String(describing: error))")
            errorMessage = "Purchased. We'll finish turning on Pro when you're online."
        }
    }

    private static func describe(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: "\(period.value)-day"
        case .week: "\(period.value * 7)-day"
        case .month: "\(period.value)-month"
        case .year: "\(period.value)-year"
        @unknown default: "Free"
        }
    }
}
