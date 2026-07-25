import UIKit
import WebKit

/// Hosts the DugOut web app in a full-screen WKWebView, served from the
/// in-process loopback server (see LocalHTTPServer.swift).
final class ViewController: UIViewController {

    /// DugOut "night-game field" background — matches --field in css/app.css.
    static let fieldGreen = UIColor(red: 0x0D / 255.0, green: 0x1F / 255.0, blue: 0x16 / 255.0, alpha: 1.0)

    private var webView: WKWebView!
    private let server = LocalHTTPServer(docRoot: Bundle.main.resourceURL!)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.fieldGreen

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = Self.fieldGreen
        webView.scrollView.backgroundColor = Self.fieldGreen
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        #if DEBUG
        // Inspect from Safari on your Mac: Develop menu → your iPhone → DugOut.
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Film-room sessions shouldn't be interrupted by auto-lock.
        UIApplication.shared.isIdleTimerDisabled = true

        do {
            let port = try server.start()
            let url = URL(string: "http://127.0.0.1:\(port)/index.html")!
            webView.load(URLRequest(url: url))
        } catch {
            showError("Couldn't start the local app server.\n\(error.localizedDescription)")
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    private func showError(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }
}

// MARK: - WKUIDelegate

extension ViewController: WKUIDelegate {

    /// Skip WebKit's per-origin camera prompt for our own bundled app.
    /// iOS still shows the one-time system Camera/Microphone permission
    /// dialogs on first use — that's the OS-level grant.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }
}

// MARK: - WKNavigationDelegate

extension ViewController: WKNavigationDelegate {

    /// Keep the app inside the webview; hand anything external (if ever added)
    /// to Safari.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        if let host = url.host, host == "127.0.0.1" || host == "localhost" {
            decisionHandler(.allow)
        } else if url.scheme == "http" || url.scheme == "https" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}
