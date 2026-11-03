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
import UserNotifications
import WebKit

/// Receives notifications from the shim, shows them in the macOS Notification Center
/// and sends a click back to the frame that created the notification.
@MainActor
final class NotificationBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "gchatNotification"

    weak var webView: WKWebView?
    var onActivate: (() -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var frames: [String: WKFrameInfo] = [:]
    private var frameOrder: [String] = []

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error {
                NSLog("%@", "Notification authorization failed: \(error.localizedDescription)")
            }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard Self.isGoogleOrigin(message.frameInfo) else {
            Log.debug("Notification rejected from \(message.frameInfo.securityOrigin.host)")
            return
        }

        guard
            let payload = message.body as? [String: Any],
            let type = payload["type"] as? String,
            let id = payload["id"] as? String
        else {
            return
        }

        let tag = payload["tag"] as? String ?? ""
        let thread = Self.limited(payload["thread"] as? String, to: Self.maximumThreadLength)

        switch type {
        case "show":
            Log.debug("Notification \(id): source=\(payload["source"] ?? "") tag=\(tag) thread=\(thread)")
            remember(frame: message.frameInfo, for: id)
            show(id: id, tag: tag, thread: thread, payload: payload)
        case "close":
            center.removeDeliveredNotifications(withIdentifiers: [identifier(id: id, tag: tag)])
        default:
            break
        }
    }

    /// The shim runs in every frame. Chat embeds frames from other origins, and a script message is
    /// delivered whatever frame posted it, so the frame's origin decides whether the payload is used.
    private static func isGoogleOrigin(_ frame: WKFrameInfo) -> Bool {
        let host = frame.securityOrigin.host.lowercased()
        return host == "google.com" || host.hasSuffix(".google.com")
    }

    private static let maximumTitleLength = 300
    private static let maximumBodyLength = 1000
    private static let maximumThreadLength = 200
    private static let maximumGroupLength = 200

    private static func limited(_ value: String?, to maximum: Int, fallback: String = "") -> String {
        guard let value, !value.isEmpty else {
            return fallback
        }

        return String(value.prefix(maximum))
    }

    /// A GroupId as Chat produces it. Anything else is not used as a click target.
    private static func isValidGroup(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= maximumGroupLength else {
            return false
        }

        return value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }

    /// A tag replaces an earlier notification with the same tag, as in the browser.
    private func identifier(id: String, tag: String) -> String {
        tag.isEmpty ? id : "tag:\(tag)"
    }

    private func remember(frame: WKFrameInfo, for id: String) {
        frames[id] = frame
        frameOrder.append(id)

        if frameOrder.count > 200 {
            frames.removeValue(forKey: frameOrder.removeFirst())
        }
    }

    /// Notification Center groups by thread. Chat's tag is unique per message, so the conversation
    /// (`dm/<id>` or `space/<id>`) is used when the shim could find it.
    private func show(id: String, tag: String, thread: String, payload: [String: Any]) {
        let content = UNMutableNotificationContent()
        content.title = Self.limited(payload["title"] as? String, to: Self.maximumTitleLength, fallback: "Google Chat")
        content.body = Self.limited(payload["body"] as? String, to: Self.maximumBodyLength)

        // Kept in userInfo so a click still knows which conversation to open after the page was
        // reloaded or the app was restarted, when the shim no longer has the notification instance.
        // Values that fail validation are left out: a click uses them as a target.
        let kind = payload["kind"] as? String ?? ""
        let group = payload["group"] as? String ?? ""
        let hasConversation = (kind == "dm" || kind == "space") && Self.isValidGroup(group)
        let target = (payload["target"] as? String)
            .flatMap(URL.init(string:))
            .flatMap { LinkPolicy.isInternal($0) ? $0 : nil }

        content.userInfo = [
            "jsId": id,
            "kind": hasConversation ? kind : "",
            "group": hasConversation ? group : "",
            "target": hasConversation ? (target?.absoluteString ?? "") : "",
        ]

        if !thread.isEmpty {
            content.threadIdentifier = thread
        } else if !tag.isEmpty {
            content.threadIdentifier = tag
        }

        if (payload["silent"] as? Bool) != true {
            content.sound = .default
        }

        let iconURL = (payload["icon"] as? String).flatMap(URL.init(string:))
        let requestIdentifier = identifier(id: id, tag: tag)

        Task {
            if let iconURL, let attachment = await Self.attachment(for: iconURL) {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: nil)

            do {
                try await center.add(request)
            } catch {
                NSLog("%@", "Showing notification failed: \(error.localizedDescription)")
            }
        }
    }

    private static let iconCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 32
        return cache
    }()

    /// Notification Center moves the attachment into its own store when the request is validated, so
    /// the file has to stay in place until then. Anything left behind is removed after an hour.
    private nonisolated static var iconFolder: URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoogleChatNotificationIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private nonisolated static func removeOldIcons(in folder: URL) {
        let cutoff = Date().addingTimeInterval(-3600)

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    /// Avatars come from Google's image hosts, so only those are fetched.
    private static func isAllowedIconURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }

        return ["google.com", "googleusercontent.com", "gstatic.com"]
            .contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Downloads the avatar and converts it to PNG, because Notification Center does not accept WebP.
    private static func attachment(for url: URL) async -> UNNotificationAttachment? {
        guard isAllowedIconURL(url) else {
            Log.debug("Notification icon rejected: \(url.host ?? "")")
            return nil
        }

        let key = url.absoluteString as NSString
        let png: Data

        if let cached = iconCache.object(forKey: key) {
            png = cached as Data
        } else if let converted = await Self.pngData(for: url) {
            iconCache.setObject(converted as NSData, forKey: key, cost: converted.count)
            png = converted
        } else {
            return nil
        }

        let folder = Self.iconFolder
        Self.removeOldIcons(in: folder)

        let file = folder
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        do {
            try png.write(to: file)
            return try UNNotificationAttachment(identifier: "icon", url: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
    }

    /// Runs off the main actor: a nonisolated async function does not inherit the caller's actor.
    /// Chat reuses the same avatar for many messages, so the result is cached by URL.
    private nonisolated static func pngData(for url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue(LinkPolicy.userAgent, forHTTPHeaderField: "User-Agent")

        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            let image = NSImage(data: data),
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            return nil
        }

        return png
    }

    private struct ClickTarget: Sendable {
        var kind = ""
        var group = ""
        var target: URL?

        init(userInfo: [AnyHashable: Any]) {
            kind = userInfo["kind"] as? String ?? ""
            group = userInfo["group"] as? String ?? ""
            target = (userInfo["target"] as? String).flatMap(URL.init(string:))
        }

        init(kind: String, group: String, target: URL?) {
            self.kind = kind
            self.group = group
            self.target = target
        }

        var isComplete: Bool { !kind.isEmpty && !group.isEmpty }
    }

    private func handleClick(jsId: String?, stored: ClickTarget) {
        onActivate?()

        guard let jsId, let webView else {
            openConversation(stored)
            return
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: [jsId]),
            let argument = String(data: data, encoding: .utf8)
        else {
            return
        }

        let script = "window.__gchatNotificationClicked && window.__gchatNotificationClicked(...\(argument))"
        let frame = frames[jsId]

        webView.evaluateJavaScript(script, in: frame, in: .page) { [weak self] result in
            switch result {
            case .success(let value):
                self?.handleClickResult(value, stored: stored)
            case .failure(let error):
                Log.debug("Notification click \(jsId) failed in frame: \(error.localizedDescription)")
                guard frame != nil else {
                    self?.openConversation(stored)
                    return
                }

                webView.evaluateJavaScript(script, in: nil, in: .page) { [weak self] result in
                    switch result {
                    case .success(let value):
                        self?.handleClickResult(value, stored: stored)
                    case .failure(let error):
                        Log.debug("Notification click \(jsId) failed in main frame: \(error.localizedDescription)")
                        self?.openConversation(stored)
                    }
                }
            }
        }
    }

    /// When the page does nothing with the click (nobody listens to service worker notifications, or
    /// the page no longer knows the notification), the app opens the conversation itself: through the
    /// sidebar first, otherwise by loading its URL.
    private func handleClickResult(_ value: Any, stored: ClickTarget) {
        let result = value as? [String: Any] ?? [:]
        Log.debug("Notification click: \(result)")

        let hasHandler = result["hasHandler"] as? Bool ?? false
        let fromServiceWorker = result["source"] as? String == "serviceWorker"

        guard !hasHandler || fromServiceWorker else {
            return
        }

        var target = stored
        if
            let kind = result["kind"] as? String, !kind.isEmpty,
            let group = result["group"] as? String, !group.isEmpty
        {
            target = ClickTarget(
                kind: kind,
                group: group,
                target: (result["target"] as? String).flatMap(URL.init(string:)) ?? stored.target
            )
        }

        openConversation(target)
    }

    private func openConversation(_ target: ClickTarget) {
        guard let webView else {
            return
        }

        guard target.isComplete else {
            if let url = target.target, LinkPolicy.isInternal(url) {
                webView.load(URLRequest(url: url))
            }
            return
        }

        guard
            let arguments = try? JSONSerialization.data(withJSONObject: [target.kind, target.group]),
            let argumentList = String(data: arguments, encoding: .utf8)
        else {
            return
        }

        let script = "window.__gchatOpenGroup ? window.__gchatOpenGroup(...\(argumentList)) : 'missing'"

        webView.evaluateJavaScript(script, in: nil, in: .page) { [weak webView] outcome in
            let opened = (try? outcome.get()) as? String == "clicked"
            Log.debug("Opening conversation \(target.kind)/\(target.group) through the sidebar: \(opened ? "succeeded" : "not found")")

            if !opened, let url = target.target, LinkPolicy.isInternal(url) {
                webView?.load(URLRequest(url: url))
            }
        }
    }
}

extension NotificationBridge: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let stored = ClickTarget(userInfo: userInfo)
        let jsId = userInfo["jsId"] as? String

        await MainActor.run {
            handleClick(jsId: jsId, stored: stored)
        }
    }
}
