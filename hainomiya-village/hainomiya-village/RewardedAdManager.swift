//
//  RewardedAdManager.swift
//  hainomiya-village
//

import UIKit
import GoogleMobileAds

final class RewardedAdManager: NSObject, GADFullScreenContentDelegate {
    static let shared = RewardedAdManager()

    private var rewardedAd: GADRewardedAd?
    private var isLoading = false
    private var pendingCompletion: ((Bool) -> Void)?

    private override init() {
        super.init()
        loadAd()
    }

    private func loadAd() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            let ad = try? await GADRewardedAd.load(withAdUnitID: AdMobConfig.rewardedAdUnitID, request: GADRequest())
            ad?.fullScreenContentDelegate = self
            rewardedAd = ad
        }
    }

    /// Presents the rewarded ad. `completion` is called with `true` only if the user
    /// watched the ad to completion and earned the reward.
    func show(from viewController: UIViewController, completion: @escaping (Bool) -> Void) {
        guard let ad = rewardedAd else {
            completion(false)
            loadAd()
            return
        }
        pendingCompletion = completion
        ad.present(fromRootViewController: viewController) { [weak self] in
            self?.pendingCompletion?(true)
            self?.pendingCompletion = nil
        }
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        pendingCompletion?(false)
        pendingCompletion = nil
        rewardedAd = nil
        loadAd()
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        pendingCompletion?(false)
        pendingCompletion = nil
        rewardedAd = nil
        loadAd()
    }
}
