# Conversation stays at the bottom after sending

Status: implemented in 1.0.0, verified working on 2026-10-30 (sending with Enter).

## Problem

After sending a message, the conversation ended at the **second-to-last** message instead of at the
bottom. Incoming messages scrolled correctly. Chrome does not show the problem.

## Behaviour

- After sending a message with Enter, the conversation stays scrolled to the bottom.
- When a list is at the bottom and its content grows or shifts without anyone scrolling, it returns to
  the bottom.
- Scrolling by the user (wheel, trackpad, scroll bar, PageUp/PageDown/Home/End/arrows/space outside a
  text field) is never overridden. Scrolling by Chat itself (for example to the first unread message)
  is respected, except during the 2 seconds after sending.

## Measurements (2026-10-30, direct message)

Message list element `div.Bl2pUd`, values are `scrollTop / scrollHeight / clientHeight`:

| Moment | Values | |
| --- | --- | --- |
| Enter pressed | 457 / 1217 / 760 | at the bottom |
| Chat sets `scrollTop = 483` | 483 / 1279 / 796 | at the bottom |
| +500 ms | 429 / 1279 / 796 | 54 px too high, no scroll API call |

- No `scrollTop` assignment, `scrollTo`, `scrollBy` or `scrollIntoView` explained the shift.
- Disabling scroll anchoring (`overflow-anchor: none`) did **not** help; the shift still happened.
- During the jump Chat calls `focus()` on the composer and the composer shrinks
  (`clientHeight` of the list 760 → 796). The exact cause in WebKit is unknown.

## Implementation

`ScrollShim` (all frames, `chat.google.com` and `mail.google.com` only):

- returns early on any other host, where no conversation list exists;
- tracks "intent": user input events and calls to the scroll APIs (`scrollTop` setter, `scroll`,
  `scrollTo`, `scrollBy`, `scrollIntoView`, `scrollIntoViewIfNeeded`) mark the next 400 ms as intended;
- a scroll event during intent pins the element when it is within 8 px of the bottom, otherwise unpins it;
- a scroll event without intent on a pinned element, any DOM mutation, or a `load` event restores pinned
  elements to the bottom on the next animation frame (using the original `scrollTop` setter);
- Enter (without Shift) in an editable element pins every scrollable element that is at the bottom and,
  for 2 seconds, ignores programmatic scrolls as intent.

## Known limitations

- Only Enter is handled as "send". Sending with the send button is not covered by the 2-second window;
  the general pinning may or may not catch it (not tested).
- The shim affects every scrollable element in Chat, not only the message list. No side effects were
  observed, but this is the first place to look if something scrolls unexpectedly.
