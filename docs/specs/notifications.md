# Notifications

Status: implemented in 1.0.0, verified working on 2026-10-30.

## Behaviour

- Every notification Google Chat creates is shown in the macOS Notification Center, with the sender's
  avatar as attachment and the default sound (unless the page asks for a silent notification).
- Notifications with the same `tag` replace each other.
- Notifications are grouped per conversation (one stack per direct message or space) when the user's
  "Group notifications" setting for the app is "Automatic".
- Notifications are also shown while the app is in the foreground (Chat itself decides whether to notify).
- Clicking a notification brings the app to the front, shows the window if it was hidden, and opens the
  conversation the notification belongs to.

## Acceptance criteria

- With the window hidden (Cmd+W), an incoming message produces a macOS notification.
- Clicking it shows the window with that conversation open, both for direct messages and for spaces.
- Chat's own "enable notifications" prompt does not appear: the page sees permission `granted`.

## Implementation

`NotificationShim` (JavaScript, all frames, document start, Google hosts only) replaces:

- `window.Notification` with `NativeNotification` (`permission` is always `granted`,
  `requestPermission()` resolves `granted`);
- `navigator.permissions.query({ name: 'notifications' })` to report `granted`;
- `ServiceWorkerRegistration.prototype.showNotification` / `getNotifications`.

Each notification is posted to the `gchatNotification` handler with `id`, `title`, `body`, `tag`,
`icon` (absolute URL), `silent`, `source` (`page` or `serviceWorker`), `thread` (`<kind>/<id>` of the
conversation, empty when not found), `kind`, `group` and `target` (the conversation URL).
`NotificationBridge` shows it with `UNUserNotificationCenter`:

- request identifier `tag:<tag>` when a tag exists, otherwise the shim's id;
- `threadIdentifier` is `thread`, falling back to the tag. The tag alone does not group anything, because
  Chat makes it unique per message (see below);
- `kind`, `group` and `target` are stored in the notification's `userInfo`, so a click still knows which
  conversation to open after the page was reloaded or the app was restarted;
- the avatar is only downloaded when it is an `https` URL on `google.com`, `googleusercontent.com` or
  `gstatic.com` (or a subdomain of those); the app would otherwise fetch a URL chosen by the page.
  Redirects are re-checked against the same hosts and a redirect elsewhere is refused, so an allowed URL
  cannot hand the download to another host. A rejected avatar leaves the notification without an
  attachment. The download (3 s timeout) and PNG
  conversion run on a background executor, because Notification Center does not accept WebP. The
  converted image is cached by URL (max 32). The PNG is written to a private folder in the temp
  directory; files in that folder older than an hour are removed when the next avatar is prepared. The
  file cannot be deleted right away: Notification Center moves it into its own store when the request is
  validated, and only failed attempts stay behind;
- the frame that created the notification is remembered (last 200) for the click.

The notification and unread shims return early unless the page host is `google.com` or a `*.google.com`
subdomain. Chat embeds frames from other origins (feedback, contacts hovercard, account cookie
rotation), and those frames must not be able to post notifications to the app.

### Message validation

`NotificationBridge` accepts `show` and `close` messages only from frames whose security origin host is
`google.com` or a `*.google.com` subdomain. A message from any other origin is dropped before the payload
is parsed; with `VerboseLogging` the rejected host is logged, never the payload.

Values are validated before they are used:

- `kind` must be `dm` or `space`;
- `group` must be 1 to 200 characters of ASCII letters, digits, `-` or `_`;
- `title` is capped at 300 characters and `body` at 1000 (the shim sends Chat's own strings);
- `thread` is capped at 200 characters.

`kind`, `group` and `target` are stored in `userInfo` only when `kind` and `group` are valid and `target`
is an internal URL, because a click uses those values as a target. Invalid values are dropped: the
notification is still shown, only without a conversation to open.

### Logging

The `Notification ...`, `Notification click ...` and `Opening conversation ...` lines contain message
ids, conversation ids and notification data, so they are only written when the `VerboseLogging` default
is `true`:

```sh
defaults write nl.baspeters.googlechat VerboseLogging -bool YES
```

The setting is read when a line is written; `defaults` changes are picked up after a relaunch.
Authorization failures and `Showing notification failed` are errors and are always logged.

### Click handling

1. `NotificationBridge` evaluates `window.__gchatNotificationClicked(id)` in the originating frame (falls
   back to the main frame). The shim fires the notification's `click` event and returns
   `{ found, source, hasHandler, kind, group, target }`.
2. If the page has no click handler, or the notification came from the service worker path, the app
   opens the conversation itself: first `window.__gchatOpenGroup(kind, id)`, which clicks the sidebar
   element `[data-group-id="<kind>/<id>"]`; if that element is not found, it loads `target`
   (`<origin><prefix>/app/chat/<id>`).
3. When the shim no longer knows the notification (`found` is false after a reload, or evaluating the
   script fails because the app was just launched), the values stored in `userInfo` replace the shim
   result, so step 2 still opens the right conversation.

## Observed Chat behaviour (2026-10-30)

- Chat uses the **service worker path** (`source = serviceWorker`), so nobody listens to the click event.
- `notification.data` is a **JSON string**, not an object, and contains no URL. Structure for a direct message (real ids replaced by placeholders):
  ```json
  ["<messageId>/<userId>",[[null,null,null,[null,"<messageId>",[null,null,["<dmId>"]]]],"<messageId>"]]
  ```
  The conversation is identified by a GroupId: `[null, null, ["<dmId>"]]` for a direct message,
  `[["<spaceId>"]]` for a space (space shape inferred from the protobuf layout, not yet observed).
- The `tag` has the form `<messageId>/<userId>`, so it is unique per message and useless for grouping.
- Grouping per conversation relies on the same GroupId. For spaces the shape is still unverified; if it
  differs, space notifications log `thread=` (empty) and are not grouped.
- Which of the two click paths (sidebar or URL) actually opened the conversation was not logged. If
  clicks stop working, check the `Opening conversation ... through the sidebar` log line first.

## Known limitations

- Notification actions (reply from the notification) are not supported (`maxActions` is 0).
- Requiring `isMainFrame` for `gchatNotification` messages is a possible follow-up, but it is not
  applied. Chat may post notifications from a subframe, so it must be verified with a live message
  before that check is added.
- If Chat changes the data format, the conversation is not found: the notification still appears, but
  clicking it only brings the app to the front. The page data is not forwarded to the app, so inspect it
  in the page with `findGroup` instead.
