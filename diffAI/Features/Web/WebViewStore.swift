import Combine
import SwiftUI
import UIKit
import WebKit

/// Owns the WKWebView so the conversation can read and act on the page while the screen is closed.
@MainActor
final class WebViewStore: NSObject, ObservableObject {
    let webView: WKWebView

    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var currentURL: URL?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // A real frame from the start, so pages lay out (and elements are "visible") even before the screen opens.
        webView = WKWebView(frame: UIScreen.main.bounds, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// Opens one of the demo pages bundled with the app. Works offline.
    func loadLocal(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "html") else {
            loadError = "The demo page \(name) is missing from the app."
            return
        }
        loadError = nil
        isLoading = true
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func load(_ url: URL) {
        loadError = nil
        isLoading = true
        webView.load(URLRequest(url: url))
    }

    /// Runs JavaScript. Scripts should return a string; nil and undefined are returned as nil, never crash.
    func evaluate(_ script: String) async -> Any? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Any?, Never>) in
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }

    /// Waits for a page in progress to finish, up to about 10 seconds.
    func waitUntilLoaded() async {
        var waited = 0
        while isLoading && waited < 100 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
    }
}

extension WebViewStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        currentURL = webView.url
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        loadError = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        loadError = error.localizedDescription
    }
}

extension WebViewStore: WKUIDelegate {
    /// Links that want a new window open in the same view instead, so "click" always does something.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// Puts the shared WKWebView on screen.
struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
