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

/// JavaScript that tracks Chat's unread state in every frame: page title, favicons and elements
/// whose aria-label contains "unread" (or the Dutch "ongelezen"). Changes are sent to `UnreadTracker`.
enum UnreadShim {
    static let source = #"""
    (() => {
        if (window.__gchatUnreadWatcher) return;
        window.__gchatUnreadWatcher = true;

        const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gchatUnread;
        if (!handler) return;

        // Chat embeds frames from other origins; only Google pages may report unread state.
        if (!/(^|\.)google\.com$/i.test(location.hostname)) return;

        const frameId = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        const unreadLabel = /unread|ongelezen/i;
        let last = '';
        let pending = false;

        const report = () => {
            pending = false;

            const icons = [...document.querySelectorAll('link[rel~="icon"]')].map((link) => link.href);
            const labels = [...document.querySelectorAll('[aria-label]')]
                .map((element) => element.getAttribute('aria-label') || '')
                .filter((label) => unreadLabel.test(label));

            const state = {
                frame: frameId,
                url: location.href,
                title: document.title,
                icons,
                labels: [...new Set(labels)].slice(0, 50),
            };

            const key = JSON.stringify(state);
            if (key === last) return;
            last = key;
            handler.postMessage(state);
        };

        const schedule = () => {
            if (pending) return;
            pending = true;
            setTimeout(report, 1000);
        };

        new MutationObserver(schedule).observe(document, {
            subtree: true,
            childList: true,
            characterData: true,
            attributes: true,
            attributeFilter: ['aria-label', 'href'],
        });

        // A frame that is removed from the page cannot report that it is gone, so the app needs a
        // heartbeat to notice, and a last message when the document unloads.
        window.addEventListener('pagehide', () => {
            handler.postMessage({ frame: frameId, gone: true });
        });

        setInterval(() => {
            handler.postMessage({ frame: frameId, alive: true });
        }, 30000);

        schedule();
    })();
    """#
}
