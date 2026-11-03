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

import Foundation

/// Decides which URLs stay in the app and which open in the default browser.
enum LinkPolicy {
    static let startURL = URL(string: "https://chat.google.com/")!

    /// Safari user agent, so Google does not block sign-in as an "embedded browser".
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    /// Google registrable domains that may stay in the app. Add a country domain here when sign-in on
    /// that domain has to work; the list is deliberately explicit instead of matching any `google` label.
    private static let googleDomains = [
        "google.com",
        "google.nl",
        "google.co.uk",
    ]

    static func isInternal(_ url: URL) -> Bool {
        // Only hosted HTTPS pages are internal. A URL without a host (`file:`, `data:`) is never one.
        guard let host = url.host?.lowercased(), url.scheme?.lowercased() == "https" else {
            return false
        }

        if host == "chat.google.com" {
            return true
        }

        if host == "mail.google.com" {
            return url.path.hasPrefix("/chat")
        }

        // Landing page for signed-out users and the sign-in flow.
        if host == "workspace.google.com" {
            return true
        }

        // YouTube's account picker, used during sign-in.
        if host == "accounts.youtube.com" {
            return url.path.hasPrefix("/accounts/")
        }

        // The sign-in flow itself runs on accounts.<domain>.
        if googleDomains.contains(where: { host == "accounts." + $0 }) {
            return true
        }

        // Cookie hand-off to a country domain, and the account pages on www.google.com.
        return (isGoogleDomainHost(host) && url.path.hasPrefix("/accounts/SetSID"))
            || (host == "www.google.com" && url.path.hasPrefix("/accounts"))
    }

    /// The registrable domain itself or its `www.` host, never another subdomain.
    private static func isGoogleDomainHost(_ host: String) -> Bool {
        googleDomains.contains { host == $0 || host == "www." + $0 }
    }

    /// Camera and microphone are only needed for Chat and Meet.
    static func allowsMediaCapture(host: String) -> Bool {
        let host = host.lowercased()
        return host == "chat.google.com" || host == "meet.google.com"
    }

    static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}
