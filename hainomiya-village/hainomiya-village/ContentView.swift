//
//  ContentView.swift
//  hainomiya-village
//
//  Created by eiki ogawa on 2026/07/26.
//

import SwiftUI
import WebKit

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            WebView(url: Bundle.main.url(forResource: "index", withExtension: "html"))
                .ignoresSafeArea(edges: [.top, .horizontal])
            BannerAdView(adUnitID: AdMobConfig.bannerAdUnitID)
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

/// Hosts the game's WKWebView and bridges the in-page "ヒント" unlock buttons to a
/// native rewarded ad: the page posts a hint id via `hintReward`, and on completion
/// we call back into `unlockHint(id)` in the page's JS.
/// Also handles auto-save/restore via `saveState` and `clearSave` message handlers.
final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let htmlURL: URL?
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
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "saveState":
            if let code = message.body as? String {
                UserDefaults.standard.set(code, forKey: Self.saveKey)
            }
        case "clearSave":
            UserDefaults.standard.removeObject(forKey: Self.saveKey)
        case "hintReward":
            guard let hintID = message.body as? String else { return }
            RewardedAdManager.shared.show(from: self) { [weak self] earned in
                guard let self else { return }
                // 広告終了後は常にAudioContextを復帰させる
                self.webView.evaluateJavaScript("resumeAudio()")
                guard earned else { return }
                let safeID = hintID.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                self.webView.evaluateJavaScript("unlockHint('\(safeID)')")
            }
        default:
            break
        }
    }
}

#Preview {
    ContentView()
}
