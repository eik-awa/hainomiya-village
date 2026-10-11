//
//  RewardedHintController.swift
//  hainomiya-village
//
//  ヒント解放用のリワード広告(Unity LevelPlay)と、その視聴回数制限。
//  制限: 1日10回まで / 3回視聴するごとに3時間のインターバル。
//

import UIKit
import IronSource

/// 視聴回数の制限を管理する。状態は UserDefaults に保存し、日付が変わると回数・インターバルともリセットする。
struct RewardLimiter {
    static let dailyLimit = 10
    static let burstSize = 3
    static let cooldown: TimeInterval = 3 * 60 * 60

    enum Availability {
        case available
        case dailyLimit
        case cooldown(until: Date)
    }

    private let defaults = UserDefaults.standard
    private let dayKey = "reward_day"
    private let countKey = "reward_count"
    private let cooldownKey = "reward_cooldown_until"

    /// 今日の開始時刻が保存値と違えば、回数とインターバルを初期化する。
    private func rollDayIfNeeded(now: Date) {
        let today = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        guard defaults.double(forKey: dayKey) != today else { return }
        defaults.set(today, forKey: dayKey)
        defaults.set(0, forKey: countKey)
        defaults.removeObject(forKey: cooldownKey)
    }

    func count(now: Date = Date()) -> Int {
        rollDayIfNeeded(now: now)
        return defaults.integer(forKey: countKey)
    }

    var cooldownUntil: Date? {
        let t = defaults.double(forKey: cooldownKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    func remaining(now: Date = Date()) -> Int {
        max(0, Self.dailyLimit - count(now: now))
    }

    func availability(now: Date = Date()) -> Availability {
        if count(now: now) >= Self.dailyLimit { return .dailyLimit }
        if let until = cooldownUntil, until > now { return .cooldown(until: until) }
        return .available
    }

    /// 報酬を付与した時点で呼ぶ。バースト(3回)を使い切ったらインターバルを開始する。
    func recordReward(now: Date = Date()) {
        let next = count(now: now) + 1
        defaults.set(next, forKey: countKey)
        if next % Self.burstSize == 0 && next < Self.dailyLimit {
            defaults.set(now.addingTimeInterval(Self.cooldown).timeIntervalSince1970, forKey: cooldownKey)
        }
    }
}

/// リワード広告の読み込み・表示と、視聴後のヒント解放を担当する。
final class RewardedHintController: NSObject, LPMRewardedAdDelegate {
    static let shared = RewardedHintController()

    /// ヒント解放を通知する(hint id)。ページ側 JS の unlockHint へ橋渡しする。
    var onUnlock: ((String) -> Void)?
    /// 残り回数やインターバルが変わったときに呼ばれる。
    var onStatusChange: (() -> Void)?
    /// 広告やダイアログがネイティブ側で閉じたときに呼ばれる(BGM 復帰用)。
    var onFinish: (() -> Void)?

    let limiter = RewardLimiter()

    private var ad: LPMRewardedAd?
    private var isLoading = false
    private var pendingHintID: String?

    private override init() { super.init() }

    /// シミュレータとデバッグ端末では本番広告を出さず、制限だけ適用して即解放する。
    private var usesRealAds: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return !DebugDeviceConfig.isDebugDevice
        #endif
    }

    // MARK: - Status

    /// ページ側へ渡す状態: (今日の残り回数, インターバル終了時刻[epoch ms]。無ければ 0)
    var status: (remaining: Int, cooldownUntilMs: Int64) {
        let remaining = limiter.remaining()
        if case .cooldown(let until) = limiter.availability() {
            return (remaining, Int64(until.timeIntervalSince1970 * 1000))
        }
        return (remaining, 0)
    }

    // MARK: - Loading

    /// SDK 初期化完了後に呼ぶ。広告が未ロードなら読み込みを始める。
    func preload() {
        guard usesRealAds, LevelPlayAdsController.shared.isInitialized else { return }
        guard !isLoading, ad?.isAdReady() != true else { return }
        let newAd = LPMRewardedAd(adUnitId: LevelPlayConfig.rewardedAdUnitID)
        newAd.setDelegate(self)
        ad = newAd
        isLoading = true
        newAd.loadAd()
    }

    private func scheduleRetry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.preload()
        }
    }

    // MARK: - Request

    func requestHint(_ hintID: String, from presenter: UIViewController) {
        guard pendingHintID == nil else { return }

        switch limiter.availability() {
        case .dailyLimit:
            showAlert("本日の視聴上限です", "広告を見て解放できるのは1日\(RewardLimiter.dailyLimit)回までです。明日またお試しください。", on: presenter)
            return
        case .cooldown(let until):
            let time = DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short)
            showAlert("インターバル中です", "広告は\(RewardLimiter.burstSize)回視聴するごとに3時間あけてください。\n\(time)以降に視聴できます。", on: presenter)
            return
        case .available:
            break
        }

        guard usesRealAds else {
            grant(hintID)
            return
        }

        guard let ad, ad.isAdReady() else {
            preload()
            showAlert("広告を準備中です", "しばらくしてからもう一度お試しください。", on: presenter)
            return
        }

        pendingHintID = hintID
        ad.showAd(viewController: presenter, placementName: nil)
    }

    private func grant(_ hintID: String) {
        limiter.recordReward()
        onUnlock?(hintID)
        onStatusChange?()
    }

    private func showAlert(_ title: String, _ message: String, on presenter: UIViewController) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.onFinish?() })
        presenter.present(alert, animated: true)
    }

    // MARK: - LPMRewardedAdDelegate

    func didLoadAd(with adInfo: LPMAdInfo) {
        isLoading = false
        print("[Rewarded] loaded")
    }

    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
        isLoading = false
        ad = nil
        print("[Rewarded] load failed (\(adUnitId)): \(error)")
        scheduleRetry()
    }

    func didDisplayAd(with adInfo: LPMAdInfo) {
        print("[Rewarded] displayed")
    }

    func didRewardAd(with adInfo: LPMAdInfo, reward: LPMReward) {
        guard let hintID = pendingHintID else { return }
        pendingHintID = nil
        grant(hintID)
    }

    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {
        print("[Rewarded] display failed: \(error)")
        pendingHintID = nil
        ad = nil
        preload()
        onFinish?()
    }

    func didCloseAd(with adInfo: LPMAdInfo) {
        // 報酬を受け取らずに閉じた場合も含め、次の広告を読み込む。
        // 報酬コールバックがクローズより後に届く場合に備え、保留中のヒントは少し遅れて破棄する。
        ad = nil
        preload()
        onFinish?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.pendingHintID = nil
        }
    }
}
