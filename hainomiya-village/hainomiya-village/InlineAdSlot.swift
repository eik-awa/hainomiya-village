//
//  InlineAdSlot.swift
//  hainomiya-village
//
//  検索結果ページの中に表示する大きめバナー(300x250)。
//  ページ側が用意した空き枠(#mrec-slot)の位置を JS から受け取り、
//  WKWebView の scrollView 上にネイティブ広告を重ねる。scrollView の子にするので、ページと一緒にスクロールする。
//

import UIKit
import WebKit
import IronSource

final class InlineAdSlotController: NSObject, LPMBannerAdViewDelegate {
    static let adSize = CGSize(width: 300, height: 250)

    private weak var webView: WKWebView?
    private weak var presenter: UIViewController?
    private var adView: UIView?
    private var isLoaded = false
    /// SDK 初期化前に届いた枠の位置。初期化完了後に反映する。
    private var pendingSlot: CGRect?

    init(webView: WKWebView, presenter: UIViewController) {
        self.webView = webView
        self.presenter = presenter
        super.init()
        NotificationCenter.default.addObserver(forName: .levelPlayDidInitialize, object: nil, queue: .main) { [weak self] _ in
            guard let self, let slot = self.pendingSlot else { return }
            self.update(slot: slot)
        }
    }

    /// シミュレータとデバッグ端末では本番広告を出さず、枠の位置確認用のプレースホルダーを置く。
    private var usesRealAds: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return !DebugDeviceConfig.isDebugDevice
        #endif
    }

    /// JS から届いた枠の位置(ドキュメント座標)で表示を更新する。nil なら隠す。
    func update(slot: CGRect?) {
        guard let slot else {
            pendingSlot = nil
            hide()
            return
        }
        pendingSlot = slot
        guard let scrollView = webView?.scrollView else { return }

        if adView == nil {
            guard let view = makeAdView() else { return }  // SDK 初期化待ち
            scrollView.addSubview(view)
            adView = view
        }
        guard let adView else { return }

        let size = Self.adSize
        adView.frame = CGRect(x: slot.minX + (slot.width - size.width) / 2, y: slot.minY, width: size.width, height: size.height)
        adView.isHidden = false
        (adView as? LPMBannerAdView)?.resumeAutoRefresh()
    }

    private func hide() {
        adView?.isHidden = true
        (adView as? LPMBannerAdView)?.pauseAutoRefresh()
    }

    private func makeAdView() -> UIView? {
        guard usesRealAds else { return makePlaceholder() }
        guard LevelPlayAdsController.shared.isInitialized, let presenter else { return nil }

        let config = LPMBannerAdViewConfigBuilder().set(adSize: .mediumRectangle()).build()
        let banner = LPMBannerAdView(adUnitId: LevelPlayConfig.inlineAdUnitID, config: config)
        banner.setDelegate(self)
        banner.loadAd(with: presenter)
        return banner
    }

    private func makePlaceholder() -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.18, alpha: 1)
        let label = UILabel()
        label.text = "[広告プレースホルダー 300x250]"
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = UIColor(white: 0.55, alpha: 1)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    // MARK: - LPMBannerAdViewDelegate

    func didLoadAd(with adInfo: LPMAdInfo) { print("[InlineAd] loaded") }
    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
        print("[InlineAd] load failed (\(adUnitId)): \(error)")
    }
    func didDisplayAd(with adInfo: LPMAdInfo) {}
    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {
        print("[InlineAd] display failed: \(error)")
    }
    func didClickAd(with adInfo: LPMAdInfo) {}
    func didLeaveApp(with adInfo: LPMAdInfo) {}
    func didExpandAd(with adInfo: LPMAdInfo) {}
    func didCollapseAd(with adInfo: LPMAdInfo) {}
}

extension Notification.Name {
    /// LevelPlay SDK の初期化が完了したときに post される。
    static let levelPlayDidInitialize = Notification.Name("levelPlayDidInitialize")
}
