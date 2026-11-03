# Google Chat for macOS

Native macOS wrapper around Google Chat (`https://chat.google.com`) in a `WKWebView`, replacing the Chrome
extension. Swift + AppKit, no Xcode project, no third-party dependencies. Licensed GPL-3.0-or-later.

Specs per feature live in [`docs/specs/`](docs/specs/), design decisions in [`docs/adr/`](docs/adr/).
Read the relevant spec before changing a feature: most features depend on observed, undocumented
behaviour of Google Chat that is recorded there.

## Commands

```sh
./scripts/build.sh            # build/Google Chat.app (ad-hoc signed)
./scripts/build.sh install    # also copies it to /Applications
./scripts/release.sh          # tag v<version> from Support/Info.plist, zip, publish with gh
```

- Builds use `swift build --build-system native`. The default SwiftPM build system fails in this
  environment with "Unknown error parsing property list" (see [ADR 0006](docs/adr/0006-swiftpm-build-without-xcode.md)).
- There are no automated tests. Verify changes in the running app (see "Verifying changes").

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/GoogleChat/` | All app code, one type per file |
| `Sources/GoogleChat/*Shim.swift` | JavaScript injected into the page, as raw string literals |
| `Support/Info.plist` | Bundle metadata, version number (source of truth for releases) |
| `Support/<lang>.lproj/` | `Localizable.strings` and `InfoPlist.strings` per language |
| `scripts/` | `build.sh`, `release.sh`, `make-icon.swift` (icon is drawn in code) |
| `docs/specs/`, `docs/adr/` | Feature specs and architecture decision records |

## Architecture in one paragraph

`AppDelegate` creates one `ChatWindowController`, which owns the `WKWebView` and injects three user
scripts at document start into **all frames**: `NotificationShim` (Notification API), `UnreadShim`
(unread state) and `ScrollShim` (keep conversation at the bottom). The scripts talk to Swift through
`WKScriptMessageHandler`s: `gchatNotification` → `NotificationBridge`, `gchatUnread` → `UnreadTracker`.
Handlers are registered through `WeakMessageHandler` to avoid a retain cycle. `LinkPolicy` decides what
stays in the app; `PopupCatcher` and `DownloadManager` handle `window.open` and downloads.

## Conventions

- **English** for code, comments, logs, docs and commit messages. No em dashes in prose.
- **Every source file starts with the GPL license header** (copy it from an existing file). In
  `Package.swift` the `swift-tools-version` line must stay first; in shell scripts the shebang.
- **User-facing strings** go through `NSLocalizedString` with the English text as key, plus a Dutch
  translation in `Support/nl.lproj/Localizable.strings`. Info.plist texts are translated in
  `InfoPlist.strings`. See [`docs/specs/localization.md`](docs/specs/localization.md).
- **Injected JavaScript** is idempotent (guarded by a `window.__gchat*` flag), uses no frameworks, and
  must not throw when `window.webkit.messageHandlers` is missing (frames on other origins).
- **Observed Chat behaviour is fragile.** When code depends on Chat's DOM, labels, data format or
  favicon names, document the observation (with an example) in the spec, and log enough to diagnose
  when Chat changes.
- Commits end with a `Co-Authored-By` line when written by an agent.

## Verifying changes

1. `./scripts/build.sh`, then start the binary directly so `NSLog` output is visible
   (`log show` did not return the app's logs in this environment):
   ```sh
   "build/Google Chat.app/Contents/MacOS/GoogleChat" > /tmp/gchat.log 2>&1 &
   ```
2. Useful log prefixes, only with `VerboseLogging` enabled: `Notification`, `Notification click`,
   `Opening conversation`, `Unread state`, `Opened externally`.
3. Inspect the page with Safari > Develop > Google Chat (only when `WebInspectorEnabled` is set).
4. Manual checklist for releases: sign in works; a message with the window hidden (Cmd+W) shows a
   notification; clicking it opens that conversation; the Dock badge matches Chat's unread count;
   after sending with Enter the conversation stays at the bottom; external links open in the browser.

## Gotchas

- The bundle identifier is `nl.baspeters.googlechat`. Changing it makes macOS treat the app as new:
  cookies (sign-in), notification permission and window state are lost.
- `PlistBuddy` rewrites `Info.plist` with tab indentation; that is expected.
- The app is ad-hoc signed and not notarized. Downloaded builds need "Open Anyway" or
  `xattr -dr com.apple.quarantine`.
