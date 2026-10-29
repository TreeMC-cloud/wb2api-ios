import SwiftUI
import WebKit

/// Full-screen WKWebView host for the wb2api console.
///
/// Design notes:
/// * One persistent `WKWebsiteDataStore.default()` keeps the console's admin
///   cookie across launches, so the user does not re-enter the key every time.
/// * The user agent is pinned to Safari-style iOS UA because upstream
///   (CodeBuddy / WorkBuddy) OAuth pages reject bare WebView UAs.
/// * OAuth authorisation opens in-system so cookies set by the identity
///   provider land in the same store the console later reads.
struct BrowserView: UIViewRepresentable {
    let url: URL?
    let allowInsecureHTTP: Bool
    let adminKey: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Upstream OAuth redirects rely on popups opening in the same session.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let controller = WKUserContentController()
        let bootstrap = WKUserScript(
            source: Coordinator.bootstrapScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(bootstrap)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = Coordinator.userAgent
        context.coordinator.webView = webView
        context.coordinator.attachObservers()
        if let url { context.coordinator.load(url) }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard let url else { return }
        // Only (re)load when the target actually changed, otherwise every
        // SwiftUI pass would blow away the running session.
        if context.coordinator.lastLoaded != url {
            context.coordinator.load(url)
        }
    }

    @MainActor
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.detachObservers()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: BrowserView
        weak var webView: WKWebView?
        var lastLoaded: URL?

        init(_ parent: BrowserView) { self.parent = parent }

        static let userAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

        /// Runs before any page script: strips `admin_key` from the address bar so
        /// the credential never survives in history or a screenshot, yet still
        /// reaches the console's prefill hook.
        static let bootstrapScript = """
        (function () {
          var u = new URL(location.href);
          var key = u.searchParams.get('admin_key') || '';
          if (key) {
            u.searchParams.delete('admin_key');
            history.replaceState(history.state, '', u.pathname + u.search + u.hash);
            globalThis.__wb2apiKey = key;
          }
          // Console reads globalThis.takeDesktopAdminKey() in app.js.
          globalThis.takeDesktopAdminKey = function () {
            var v = globalThis.__wb2apiKey || '';
            globalThis.__wb2apiKey = '';
            return v;
          };
        })();
        """

        func load(_ url: URL) {
            lastLoaded = url
            guard let webView else { return }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadRevalidatingCacheData
            webView.load(request)
        }

        @MainActor
        func attachObservers() {
            NotificationCenter.default.addObserver(
                self, selector: #selector(reload),
                name: .wb2apiReloadRequested, object: nil
            )
        }

        @MainActor
        func detachObservers() { NotificationCenter.default.removeObserver(self) }

        @objc private func reload() {
            if let current = webView?.url, current.absoluteString != "about:blank" {
                webView?.reload()
            } else if let url = parent.url {
                load(url)
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""

            // Custom schemes (weixin://, alipays://, ...) hand off to the OS.
            if !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            // ATS already blocks plain HTTP unless NSAllowsArbitraryLoads is on;
            // this is the second gate for the explicit "allow insecure" toggle.
            if scheme == "http", !parent.allowInsecureHTTP {
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                // target=_blank links (the console's auth-link) stay in-app.
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            // Self-signed certificates are common on a LAN host. Only accept
            // them when the user explicitly opted into insecure transport;
            // otherwise fall back to the system's default validation.
            let space = challenge.protectionSpace
            guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  parent.allowInsecureHTTP,
                  let trust = space.serverTrust
            else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastLoaded = webView.url ?? lastLoaded
        }

        // MARK: - WKUIDelegate

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            present(title: "提示", message: message) { completionHandler() }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            let alert = UIAlertController(title: "确认", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
            topController()?.present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
                completionHandler(alert?.textFields?.first?.text)
            })
            topController()?.present(alert, animated: true)
        }

        // MARK: - Helpers

        private func present(title: String, message: String, completion: @escaping () -> Void) {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completion() })
            topController()?.present(alert, animated: true)
        }

        private func topController() -> UIViewController? {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }
    }
}
