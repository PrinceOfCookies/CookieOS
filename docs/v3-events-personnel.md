# CookieOS v3 events, personnel, and monitors

## Event broker

The `events` service retains a bounded history per topic and supports authenticated
subscriptions. Publishers must run locally or appear in `events.publishers`; enable
signed networking before trusting a remote publisher.

Built-in producers currently publish `node.started`, `security.changed`,
`auth.user.changed`, `personnel.ready`, `player.online`, and `player.offline`.
Subscriptions expire automatically and must be renewed by long-running displays.

## Personnel

The `personnel` service reads directly from the central Auth authority and exposes
list, search, and summary endpoints. Filters include `all`, `active`, `fired`,
`visitors`, and `cl0` through `cl5`. It does not maintain a second user database.

## Monitor UI

`cookieos.ui.monitor` supplies monitor discovery, clearing, headers, centered text,
bounded lines, truncation, and consistent status colors. The `personnel-display`
service demonstrates responsive layouts: wide monitors include role columns, while
narrow monitors retain clearance, name, and status.

Add `personnel-display` to the same authority node as `personnel` when that computer
has a monitor. Configure its side, scale, refresh rate, and filter under
`personnelDisplay`.

The old Gemini chat background event has been removed. The ordinary local chat-box
program remains available and is unrelated to Gemini.
