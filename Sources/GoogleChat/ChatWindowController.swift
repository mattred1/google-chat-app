// Google Chat for macOS
// Copyright (C) 2026 Bas Peters
//
// This program is free software: you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
// even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program. If not,
// see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import WebKit

@MainActor
final class ChatWindowController: NSWindowController, NSWindowDelegate {
    private static let frameName = "MainWindow"
    private static let zoomKey = "pageZoom"
    /// Off by default: the Web Inspector lets Safari attach to the signed-in session.
    private static let inspectorKey = "WebInspectorEnabled"

    private let webView: WKWebView
    private let downloads = DownloadManager()
    private let unread = UnreadTracker()
    private var popups: [PopupCatcher] = []
    private var titleObservation: NSKeyValueObservation?

    init(notifications: NotificationBridge) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        Self.disableBackgroundSuppression(configuration.preferences)

        let contentController = configuration.userContentController
        contentController.addUserScript(WKUserScript(
            source: NotificationShim.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        contentController.add(WeakMessageHandler(notifications), name: NotificationBridge.messageName)
        contentController.addUserScript(WKUserScript(
            source: UnreadShim.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        contentController.addUserScript(WKUserScript(
            source: ScrollShim.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = LinkPolicy.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = UserDefaults.standard.bool(forKey: Self.inspectorKey)

        let storedZoom = UserDefaults.standard.double(forKey: Self.zoomKey)
        webView.pageZoom = storedZoom > 0 ? storedZoom : 1

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Google Chat"
        window.minSize = NSSize(width: 480, height: 400)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentView = webView

        if !window.setFrameUsingName(Self.frameName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameName)

        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        notifications.webView = webView
        configuration.userContentController.add(WeakMessageHandler(unread), name: UnreadTracker.messageName)

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.titleDidChange(webView.title)
            }
        }

        webView.load(URLRequest(url: LinkPolicy.startURL))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// WebKit heavily throttles pages in an invisible window. This (private) preference keeps
    /// the chat connection active while the window is hidden.
    private static func disableBackgroundSuppression(_ preferences: WKPreferences) {
        let setter = NSSelectorFromString("_setPageVisibilityBasedProcessSuppressionEnabled:")

        if preferences.responds(to: setter) {
            preferences.setValue(false, forKey: "pageVisibilityBasedProcessSuppressionEnabled")
        }
    }

    private func titleDidChange(_ title: String?) {
        let title = title ?? ""
        window?.title = title.isEmpty ? "Google Chat" : title
    }

    // MARK: Window

    /// Closing only hides the window, so messages and notifications keep coming in.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: Menu actions

    @objc func reloadPage(_ sender: Any?) {
        webView.reload()
    }

    @objc func goBack(_ sender: Any?) {
        webView.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        webView.goForward()
    }

    @objc func goHome(_ sender: Any?) {
        webView.load(URLRequest(url: LinkPolicy.startURL))
    }

    @objc func zoomIn(_ sender: Any?) {
        setZoom(webView.pageZoom + 0.1)
    }

    @objc func zoomOut(_ sender: Any?) {
        setZoom(webView.pageZoom - 0.1)
    }

    @objc func resetZoom(_ sender: Any?) {
        setZoom(1)
    }

    private func setZoom(_ zoom: CGFloat) {
        let clamped = min(max(zoom, 0.5), 3)
        webView.pageZoom = clamped
        UserDefaults.standard.set(Double(clamped), forKey: Self.zoomKey)
    }
}

// MARK: - Navigation

extension ChatWindowController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if ["mailto", "tel", "facetime", "zoommtg", "msteams"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false

        if isMainFrame, navigationAction.navigationType == .linkActivated, LinkPolicy.isWeb(url), !LinkPolicy.isInternal(url) {
            Log.debug("Opened externally: \(url.absoluteString)")
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = downloads
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = downloads
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        unread.reset()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - UI

extension ChatWindowController: WKUIDelegate {
    /// `target="_blank"` and `window.open`: Chat and sign-in stay in the app, everything else opens in the default browser.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, LinkPolicy.isWeb(url) {
            openPopupURL(url)
            return nil
        }

        // window.open() without a URL only gets an address later; catch it in an invisible web view.
        let popup = PopupCatcher(
            configuration: configuration,
            open: { [weak self] url in self?.openPopupURL(url) },
            onFinish: { [weak self] catcher in self?.popups.removeAll { $0 === catcher } }
        )
        popups.append(popup)
        return popup.webView
    }

    private func openPopupURL(_ url: URL) {
        if LinkPolicy.isInternal(url) {
            webView.load(URLRequest(url: url))
        } else {
            Log.debug("Opened externally: \(url.absoluteString)")
            NSWorkspace.shared.open(url)
        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true

        guard let window else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
            return
        }

        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"))
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Button"))
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(LinkPolicy.allowsMediaCapture(host: origin.host) ? .grant : .prompt)
    }
}

/// Prevents a retain cycle between the WKUserContentController and the bridge.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
