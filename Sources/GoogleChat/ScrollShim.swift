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

/// JavaScript that keeps a conversation at the bottom after sending a message.
///
/// Chat scrolls to the bottom after sending, but in WebKit the list shifts up again shortly after
/// (when the composer is focused and shrinks), ending at the second-to-last message. This script
/// keeps a list at the bottom until the user or Chat itself scrolls elsewhere. Right after sending,
/// only scrolling by the user counts.
enum ScrollShim {
    static let source = #"""
    (() => {
        if (window.__gchatStickToBottom) return;
        window.__gchatStickToBottom = true;

        // Only the Chat pages have a conversation list to keep at the bottom.
        if (location.hostname !== 'chat.google.com' && location.hostname !== 'mail.google.com') return;

        const threshold = 8;
        const pinned = new Set();
        let intentUntil = 0;
        let sentUntil = 0;
        let scheduled = false;

        const now = () => Date.now();
        const markIntent = () => { intentUntil = now() + 400; };
        const markProgrammatic = () => { if (now() >= sentUntil) markIntent(); };
        const distanceToBottom = (element) => element.scrollHeight - element.scrollTop - element.clientHeight;
        const isEditable = (element) => element instanceof Element && element.closest('input, textarea, [contenteditable=""], [contenteditable="true"]');

        // Scrolling by the user: scroll wheel, trackpad, scroll bar or navigation keys outside a text field.
        addEventListener('wheel', markIntent, { capture: true, passive: true });
        addEventListener('touchmove', markIntent, { capture: true, passive: true });
        addEventListener('pointerdown', (event) => {
            if (event.target instanceof Element && event.target.scrollHeight > event.target.clientHeight) markIntent();
        }, { capture: true, passive: true });
        addEventListener('keydown', (event) => {
            if (!isEditable(event.target) && ['PageUp', 'PageDown', 'Home', 'End', 'ArrowUp', 'ArrowDown', ' '].includes(event.key)) markIntent();
        }, { capture: true, passive: true });

        // Enter in the composer sends a message: lists at the bottom stay there.
        addEventListener('keydown', (event) => {
            if (event.key !== 'Enter' || event.shiftKey || !isEditable(event.target)) return;
            sentUntil = now() + 2000;
            intentUntil = 0;
            for (const element of document.querySelectorAll('*')) {
                if (element.scrollHeight > element.clientHeight && distanceToBottom(element) <= threshold) pinned.add(element);
            }
        }, { capture: true, passive: true });

        // Scrolling by Chat itself (for example to the first unread message) also counts as intended.
        const wrap = (name) => {
            const original = Element.prototype[name];
            if (typeof original !== 'function') return;
            Element.prototype[name] = function (...args) {
                markProgrammatic();
                return original.apply(this, args);
            };
        };
        ['scrollIntoView', 'scrollIntoViewIfNeeded', 'scrollTo', 'scrollBy', 'scroll'].forEach(wrap);

        const scrollTop = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollTop');
        if (scrollTop && scrollTop.set) {
            Object.defineProperty(Element.prototype, 'scrollTop', {
                configurable: true,
                get() { return scrollTop.get.call(this); },
                set(value) {
                    markProgrammatic();
                    scrollTop.set.call(this, value);
                },
            });
        }

        const restore = () => {
            scheduled = false;
            for (const element of pinned) {
                if (!element.isConnected) {
                    pinned.delete(element);
                } else if (distanceToBottom(element) > 1) {
                    scrollTop.set.call(element, element.scrollHeight);
                }
            }
        };

        const schedule = () => {
            if (scheduled || pinned.size === 0) return;
            scheduled = true;
            requestAnimationFrame(restore);
        };

        document.addEventListener('scroll', (event) => {
            const element = event.target;
            if (!(element instanceof Element) || element.scrollHeight <= element.clientHeight) return;

            if (now() < intentUntil) {
                if (distanceToBottom(element) <= threshold) pinned.add(element); else pinned.delete(element);
            } else if (pinned.has(element)) {
                // Shifted without anyone scrolling: back to the bottom.
                schedule();
            }
        }, { capture: true, passive: true });

        new MutationObserver(schedule).observe(document, { subtree: true, childList: true, characterData: true });
        document.addEventListener('load', schedule, { capture: true, passive: true });
    })();
    """#
}
