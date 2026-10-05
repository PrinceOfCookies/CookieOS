# CookieSecurity Command Center

Run `login`, then `console [monitor-name]`, on a CookieSecurity terminal with an attached monitor. Press Q or Backspace to leave the console. Adjacent advanced-monitor blocks form a native CC:Tweaked monitor wall; named wired monitors can be selected explicitly. Every view and action uses the current authenticated session and remains subject to Command Authority lockdown and normal clearance checks.

The touch interface contains Overview, Map, Incidents, People, Devices, Alerts, Tasks, Policies, Audit, Updates, and Simulation tabs. It refreshes every five seconds. An orange `[SIMULATION]` banner is always shown while an exercise is active.

## Visual map editor

Open Map and use `-` or `+` to change floors. Touch ADD and then an empty map position; enter the room id and label on the terminal. Touch a room to select it and DEL to remove it. Map changes are durable and immediately available to other displays.
Active alarms are overlaid in red. Rooms may also define optional world-coordinate bounds through `map.room.set`; online players inside those bounds appear as green initials.

## Policies and approval

Normal, night, restricted, evacuation, and lockdown profiles are included. Touching a policy applies it. Restricted and lockdown policies require a two-person approval:

```
approve request policy:lockdown
approve <approval-id>
policy lockdown <approval-id>
```

The requester and approver must be different users. Approvals expire after five minutes and are consumed once.

## Credentials

- `passissue <CL> [seconds]` creates a one-use visitor pass.
- `passlogin <code>` redeems it on a terminal.
- `userpolicy <user> <zone1,zone2|*> [expiry-epoch]` limits zones and expiration.
- `credrevoke <user>` immediately revokes a lost credential and its sessions.

The Auth API also supports access-hour schedules, forced password changes, temporary accounts, and explicit expiration. CL6 remains exclusive to Command Authority.
Passwords default to a 90-day maximum age; users can still authenticate to replace an expired or forced-change password, but other permissions remain unavailable until they do.

## Alarms, workflows, and notifications

Alarm patterns define sound, count, priority, and escalation delay. Unacknowledged alarms escalate automatically. Drills publish visible drill events without initiating a real lockdown. Included workflows cover fire, intrusion, missing person, medical emergency, evacuation, shelter-in-place, and communications failure.

Notifications may target monitors, chat, speakers, and subscribed pocket terminals. Stock speakers provide priority cues; announcement text is delivered through event/chat/display consumers.

Device management tracks attach, disappearance, restoration/replacement, free storage, and turtle fuel. Friendly names and reusable type-checked configuration templates are available through `device.rename`, `device.template.set`, and `device.template.apply`. Offline entries include likely cable, chunk-loading, and type-mismatch diagnostics.

## Tasks and patrols

Tasks have owner, zone, due time, priority, and status. Patrol checkpoint records are timestamped and published as events. These can feed automation rules for missed checks and shift handover dashboards.
Patrol routes can define required checkpoints and an interval; missing the deadline produces a warning notification and `patrol.missed` event. Shift notes are stored through `handover.add` and queried through `handover.list`.

## Simulation safety

Simulation mode records policy actions and injected failures in a separate exercise timeline. Simulated policies, alarms, doors, and announcements do not operate live hardware. Real controls remain visibly marked with the orange simulation banner until the exercise is stopped.

## Audit investigations

`auditfind`, `auditverify`, and `auditexport` provide full-text filtering, hash-chain verification, and export to `/cookieos-data/exports` or an attached `/disk`. Filters are also available for actor, node, action, outcome, and time range through `audit.query`.
