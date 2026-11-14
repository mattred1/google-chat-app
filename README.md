# Google Chat for macOS

A native macOS app (Swift, AppKit and WKWebView) for Google Chat, as a replacement for the Chrome extension.

The app follows the language of your Mac: English by default, Dutch when macOS is set to Dutch.

## Installation

Download the latest zip from [Releases](https://github.com/mattred1/google-chat-app/releases), unzip it
and drag **Google Chat.app** to your Applications folder. The app is not notarized by Apple. If macOS says
the app cannot be opened, go to System Settings > Privacy & Security and click **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/Google Chat.app"
```

Requires macOS 14 or later.

## Building

You only need the Command Line Tools, not Xcode.

```sh
./scripts/build.sh           # builds build/Google Chat.app
./scripts/build.sh install   # builds and copies it to /Applications
```

## Creating a release

1. Increase `CFBundleShortVersionString` (and `CFBundleVersion`) in `Support/Info.plist` and commit it.
2. Run `./scripts/release.sh`. It creates and pushes the `v<version>` tag to `origin`.
3. The `Release` GitHub Actions workflow builds the app and attaches
   `Google-Chat-<version>.zip` to a release in that repository. Download it from
   [Releases](https://github.com/mattred1/google-chat-app/releases) after the workflow completes.

For the workflow to publish releases, enable GitHub Actions for the repository and allow workflows
to have read and write permissions. A version bump alone does not publish a release; the `v<version>`
tag must be pushed.

## Features

- **Notifications**: WKWebView does not support the Web Notification API. `NotificationShim` replaces
  `window.Notification` (and `showNotification` of service workers) and forwards every notification to
  `NotificationBridge`, which shows it in the macOS Notification Center with the sender's avatar.
  Clicking a notification brings the app to the front and opens the right conversation.
- **Runs in the background**: Cmd+W only hides the window. App Nap and the throttling of hidden pages
  are disabled, so messages keep coming in. Quit with Cmd+Q.
- **Dock badge** with the number of unread messages, read from the Home shortcut in Chat. When there is
  no number but the favicon shows a dot, the badge shows a dot.
- **Conversation stays at the bottom after sending**: in WebKit, a conversation shifts to the
  second-to-last message after sending. `ScrollShim` keeps it at the bottom.
- **Links** outside Chat (Drive, Meet, websites) open in your default browser.
- **Attachments** can be uploaded through the file dialog and are downloaded to `~/Downloads`.
- Your sign-in, zoom level (Cmd+ / Cmd- / Cmd0) and window position are remembered.
- **Localized**: menus, buttons and permission prompts follow the system language (English and Dutch).
  Translations live in `Support/<language>.lproj/`.

## Testing and debugging

The web view can be inspected: Safari > Develop > Google Chat. A test notification from the console:

```js
new Notification('Test', { body: 'Hello from Google Chat' })
```

If nothing appears, check System Settings > Notifications > Google Chat, and in Chat itself
(Settings > Notifications) whether browser notifications are enabled.

The unread count is read from Chat's labels in English and Dutch. In other languages the badge falls
back to a dot.

## Documentation

- [`docs/specs/`](docs/specs/): one spec per feature, including the observed Google Chat behaviour it relies on.
- [`docs/adr/`](docs/adr/): architecture decision records.
- [`CLAUDE.md`](CLAUDE.md): context and conventions for AI coding agents.

## Structure

| File | Purpose |
| --- | --- |
| `AppDelegate.swift` | Startup, reopening from the Dock, disabling App Nap |
| `ChatWindowController.swift` | Window, web view, navigation, uploads |
| `NotificationShim.swift` | JavaScript that emulates the Notification API |
| `NotificationBridge.swift` | Bridge to UNUserNotificationCenter; opens the right conversation on click |
| `UnreadShim.swift`, `UnreadTracker.swift`, `UnreadCount.swift` | Reading the unread state for the Dock badge |
| `ScrollShim.swift` | Keeping a conversation at the bottom after sending |
| `LinkPolicy.swift` | Which URLs stay in the app |
| `PopupCatcher.swift` | Sending `window.open()` without a URL to the browser |
| `DownloadManager.swift` | Downloads to `~/Downloads` |
| `MainMenu.swift` | Menu bar (required for copy and paste) |

## License

Copyright (C) 2026 Bas Peters

This project is licensed under the [GNU General Public License v3.0](LICENSE). You may use, modify and
distribute the code, as long as derived versions are released under the same license and the source code
remains available.

This app is not made by or affiliated with Google. "Google Chat" is a trademark of Google LLC.
