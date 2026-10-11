//
//  AdBannerView.swift
//  hainomiya-village
//
//  画面最下部に常時表示する Unity LevelPlay(Unity Ads)バナー。
//

import SwiftUI
import IronSource

/// LevelPlay SDK の初期化状態をアプリ全体で共有する。
/// バナー広告オブジェクトは初期化完了(onInitSuccess)後に生成する必要があるため、
/// AdBannerView はこの状態を監視してから広告を生成する。
@Observable
final class LevelPlayAdsController {
    static let shared = LevelPlayAdsController()

    private(set) var isInitialized = false

    private init() {}

    func initialize() {
        guard !isInitialized else { return }
        #if targetEnvironment(simulator)
        // シミュレータは IDFA が無くテストデバイス登録が効かないため SDK を起動しない。
        print("[AdBanner] simulator: skipping SDK init")
        return
        #else
        // Test Suite はこのメタデータを有効にしてから初期化しないと起動できない。
        // デバッグ端末以外では本番の広告配信に影響しないよう有効化しない。
        if DebugDeviceConfig.isDebugDevice {
            LevelPlay.setMetaDataWithKey("is_test_suite", value: "enable")
        }
        let request = LPMInitRequestBuilder(appKey: LevelPlayConfig.appKey).build()
        LevelPlay.initWith(request) { [weak self] _, error in
            if let error = error {
                print("[AdBanner] init failed: \(error)")
                return
            }
            print("[AdBanner] init success")
            DispatchQueue.main.async {
                self?.isInitialized = true
                RewardedHintController.shared.preload()
                NotificationCenter.default.post(name: .levelPlayDidInitialize, object: nil)
            }
        }
        #endif
    }

    /// デバッグ端末(DebugDeviceConfig.isDebugDevice)からのみ呼び出す想定。
    /// LevelPlay の Test Suite を起動し、テストモードで広告在庫を確認できるようにする。
    func launchTestSuite() {
        guard let vc = UIApplication.shared.kwRootViewController else { return }
        LevelPlay.launchTestSuite(vc)
    }
}

/// LevelPlay バナー(320x50)を SwiftUI へ橋渡しする。
private struct AdBannerUIView: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LPMBannerAdView {
        let config = LPMBannerAdViewConfigBuilder().set(adSize: .banner()).build()
        let banner = LPMBannerAdView(adUnitId: adUnitID, config: config)
        banner.setDelegate(context.coordinator)
        if let vc = UIApplication.shared.kwRootViewController {
            banner.loadAd(with: vc)
            context.coordinator.requestedLoad = true
        }
        return banner
    }

    func updateUIView(_ uiView: LPMBannerAdView, context: Context) {
        // ルート VC がまだ無かった場合に備えて、表示更新時に補う。
        if !context.coordinator.requestedLoad, let vc = UIApplication.shared.kwRootViewController {
            uiView.loadAd(with: vc)
            context.coordinator.requestedLoad = true
        }
    }

    final class Coordinator: NSObject, LPMBannerAdViewDelegate {
        var requestedLoad = false

        func didLoadAd(with adInfo: LPMAdInfo) {
            print("[AdBanner] banner loaded: \(adInfo.adUnitId)")
        }
        func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
            print("[AdBanner] banner load failed (\(adUnitId)): \(error)")
        }
        func didDisplayAd(with adInfo: LPMAdInfo) {
            print("[AdBanner] banner displayed")
        }
        func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {
            print("[AdBanner] banner display failed: \(error)")
        }
        func didClickAd(with adInfo: LPMAdInfo) {}
        func didLeaveApp(with adInfo: LPMAdInfo) {}
        func didExpandAd(with adInfo: LPMAdInfo) {}
        func didCollapseAd(with adInfo: LPMAdInfo) {}
    }
}

/// シミュレータ用のダミーバナー。
private struct SimulatorAdPlaceholder: View {
    var body: some View {
        ZStack {
            Color(white: 0.18)
            Text("[広告プレースホルダー / テスト用]")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(Color(white: 0.55))
        }
    }
}

/// デバッグ端末用のプレースホルダー。タップすると LevelPlay の Test Suite が起動する。
private struct DebugAdPlaceholder: View {
    var body: some View {
        ZStack {
            Color(white: 0.18)
            Text("テストモード")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(Color(white: 0.55))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            LevelPlayAdsController.shared.launchTestSuite()
        }
    }
}

/// SDK 初期化完了後にバナーを表示する。シミュレータではプレースホルダーを表示。
/// デバッグ端末(DebugDeviceConfig.isDebugDevice)では本番広告を配信せずプレースホルダーを表示する。
struct AdBannerView: View {
    let adUnitID: String
    @State private var ads = LevelPlayAdsController.shared

    var body: some View {
        #if targetEnvironment(simulator)
        SimulatorAdPlaceholder()
        #else
        if DebugDeviceConfig.isDebugDevice {
            DebugAdPlaceholder()
        } else if ads.isInitialized {
            AdBannerUIView(adUnitID: adUnitID)
        }
        #endif
    }
}

extension UIApplication {
    /// 現在キーになっているウインドウのルート ViewController。
    var kwRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
