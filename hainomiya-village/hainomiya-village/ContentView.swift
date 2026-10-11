//
//  ContentView.swift
//  hainomiya-village
//
//  Created by eiki ogawa on 2026/07/26.
//

import SwiftUI
import WebKit
import StoreKit

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            WebView(url: Bundle.main.url(forResource: "index", withExtension: "html"))
                .ignoresSafeArea(edges: [.top, .horizontal])
            AdBannerView(adUnitID: LevelPlayConfig.bannerAdUnitID)
                .frame(height: 50)
        }
        .ignoresSafeArea(edges: .top)
    }
}

struct WebView: UIViewControllerRepresentable {
    let url: URL?

    func makeUIViewController(context: Context) -> WebViewController {
        WebViewController(htmlURL: url)
    }

    func updateUIViewController(_ uiViewController: WebViewController, context: Context) {}
}

/// Hosts the game's WKWebView and bridges the in-page "ヒント" unlock buttons: the
/// page posts a hint id via `hintReward`, and once the rewarded ad has been watched
/// (subject to the daily limit / cooldown) we call back into `unlockHint(id)` in the page's JS.
/// Also handles auto-save/restore via `saveState` and `clearSave` message handlers.
final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let htmlURL: URL?
    private var inlineAd: InlineAdSlotController?
    private static let saveKey = "hainomiya_save"

    init(htmlURL: URL?) {
        self.htmlURL = htmlURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let contentController = WKUserContentController()
        contentController.add(self, name: "hintReward")
        contentController.add(self, name: "saveState")
        contentController.add(self, name: "clearSave")
        contentController.add(self, name: "requestReview")
        contentController.add(self, name: "adSlot")
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let htmlURL {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        inlineAd = InlineAdSlotController(webView: webView, presenter: self)

        let rewarded = RewardedHintController.shared
        rewarded.onUnlock = { [weak self] hintID in
            let safeID = hintID.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            self?.webView.evaluateJavaScript("unlockHint('\(safeID)')")
        }
        rewarded.onStatusChange = { [weak self] in self?.pushAdStatus() }
        rewarded.onFinish = { [weak self] in self?.webView.evaluateJavaScript("resumeAudio()") }
        // 日付またはインターバルが変わっている可能性があるので、前面に戻るたびに状態を送り直す。
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pushAdStatus()
        }
    }

    /// 広告の残り回数とインターバルをページ側に渡す(ノートの表示用)。制限の判定自体はネイティブ側が行う。
    private func pushAdStatus() {
        let status = RewardedHintController.shared.status
        webView.evaluateJavaScript("setAdStatus(\(status.remaining),\(status.cooldownUntilMs))")
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pushAdStatus()
        if let savedCode = UserDefaults.standard.string(forKey: Self.saveKey), !savedCode.isEmpty {
            let safe = savedCode
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("nativeAutoRestore('\(safe)')")
        }
        webView.evaluateJavaScript("startAudioIfNeeded()")
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { [weak self] _ in
            completionHandler(false)
            self?.webView.evaluateJavaScript("resumeAudio()")
        })
        alert.addAction(UIAlertAction(title: "やり直す", style: .destructive) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    // MARK: - Review

    /// エンディング到達後のレビュー依頼。同じバージョンでは一度だけ依頼する(表示可否は iOS が判断する)。
    private func requestReviewOncePerVersion() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let key = "review_requested_version"
        guard UserDefaults.standard.string(forKey: key) != version,
              let scene = view.window?.windowScene else { return }
        UserDefaults.standard.set(version, forKey: key)
        AppStore.requestReview(in: scene)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "saveState":
            if let code = message.body as? String {
                UserDefaults.standard.set(code, forKey: Self.saveKey)
            }
        case "clearSave":
            UserDefaults.standard.removeObject(forKey: Self.saveKey)
        case "adSlot":
            // ページ内の広告枠の位置(ドキュメント座標)。visible=false か不正な値なら隠す。
            guard let dict = message.body as? [String: Any],
                  dict["visible"] as? Bool == true,
                  let x = (dict["x"] as? NSNumber)?.doubleValue,
                  let y = (dict["y"] as? NSNumber)?.doubleValue,
                  let w = (dict["w"] as? NSNumber)?.doubleValue,
                  let h = (dict["h"] as? NSNumber)?.doubleValue else {
                inlineAd?.update(slot: nil)
                return
            }
            inlineAd?.update(slot: CGRect(x: x, y: y, width: w, height: h))
        case "requestReview":
            requestReviewOncePerVersion()
        case "hintReward":
            guard let hintID = message.body as? String else { return }
            RewardedHintController.shared.requestHint(hintID, from: self)
        default:
            break
        }
    }
}

#Preview {
    ContentView()
}
