# Unread badge

Status: implemented in 1.0.0, verified working on 2026-10-30.

## Behaviour

- The Dock icon shows the number of unread messages, matching the count Chat shows on its Home shortcut.
- When no number can be found but Chat signals unread messages through its favicon, the badge shows `•`.
- Without unread messages, the badge is empty.

## Implementation

`UnreadShim` (all frames, Google hosts only) reports per frame, at most once per second and only on
change, to the `gchatUnread` handler: a random frame id, URL, `document.title`, favicon URLs and the
distinct `aria-label`s that contain `unread` or `ongelezen` (max 50). It also sends a heartbeat every 30
seconds and a final `gone` message on `pagehide`.

The unread shim returns early unless the page host is `google.com` or a `*.google.com` subdomain. Chat
embeds frames from other origins (feedback, contacts hovercard, account cookie rotation), and those
frames must not be able to post unread state to the app. `UnreadTracker` enforces the same rule on the
message itself (`message.frameInfo.securityOrigin`), because the handler is registered on the shared
content controller and is therefore reachable from every frame, whether or not the shim installed.

Dynamic values in `NSLog` messages are passed with a fixed format string (`"%@"`), never interpolated
into the format string itself. Page URLs and labels can contain percent-encoded text that would
otherwise be interpreted as formatting directives.

`Unread state ...` and `Unread frame removed` contain page URLs, titles and labels, so they are only
written when the `VerboseLogging` default is `true` (see
[notifications](notifications.md#logging)). The badge itself never logs.

`UnreadTracker` keeps the latest state per frame id (reset on every main-frame `didCommit`) and computes
the badge with `UnreadCount`:

1. count from the title (`(3)` or `3 unread`), taking the maximum across frames;
2. count from labels: the number in the **Home shortcut** label if present, otherwise the highest
   `<n> unread` number in any label; labels without a number are ignored;
3. badge = the higher of 1 and 2; if that is 0 and a favicon URL matches `(?<!no_)dot|notif|unread|badge`, `•`.

A heartbeat never replaces the stored state, it only refreshes when the frame was last heard from.
Frames from subframes that stay silent for 120 seconds are removed (logged as `Unread frame removed`),
because removing an iframe does not let it report that it is gone. The main frame is never pruned by
timeout: it holds the Home shortcut, and WebKit may throttle timers in subframes or a hidden page. At
most 50 frames are kept. `SuspendingClock` is used for the timeout, so waking the Mac does not discard
every frame.

## Observed Chat behaviour (2026-10-30, Dutch UI)

- The page title is just `Chat`; it never contains a count. (This was the first, failed approach.)
- Relevant labels: `Snelkoppeling Home, 1 ongelezen bericht` (Home shortcut, the total) and
  `1 ongelezen bericht`.
- Noise labels that must not be counted: `Filter Ongelezen aan-/uitzetten`, `Ongelezen`,
  `Markeren als ongelezen`. Counting every matching label gave 5 instead of 1.
- Favicon without unread messages:
  `https://ssl.gstatic.com/dynamite/images/favicons_20260602/chat_2026_logo_favicon_no_dot_64px.png`.
  The variant with unread messages was not observed; a name containing `dot` without `no_` is assumed.
- Many third-party frames (feedback, contacts hovercard, Workspace side panel, account cookie rotation)
  reported before the host guard was added; they have no labels and were ignored by the computation, and
  they can no longer report at all.

## Known limitations

- Counts are only parsed for English and Dutch labels. Chat's language follows the Google account, not
  macOS; in other languages the badge falls back to the favicon dot.
- The badge is set by the app, not by Notification Center (`badge` authorization is requested but unused).
