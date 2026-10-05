# CookieSecurity Operations Guide

CookieSecurity 3.6 adds an operations layer without granting remote shell or arbitrary remote filesystem access. Administrative actions remain permission checked, signed by the node transport, audited where appropriate, and blocked whenever Command Authority is locked or unavailable.

## Operations dashboard

Run `dashboard` for a network snapshot or `dashboard monitor` for a monitor-sized node board. It shows discovered nodes, age, role, location, open incidents, doors, rooms, rules, and rollout plans.

## Accounts and permissions

Auth owns CL0-CL5 accounts. Use `useradd`, `userdel`, `passwd`, `permadd`, and `permdel` from an authenticated terminal. CL6 remains local to Command Authority and cannot be created through Auth.

## Communications

- `chat Hello` sends to the global channel.
- `chat #security Message` sends to a named channel.
- `announce urgent Message` emits an announcement and plays its speaker-zone cue.
- Announcement priorities are `normal`, `urgent`, and `emergency`.

Stock CC:Tweaked speakers cannot synthesize arbitrary text. Announcement text is carried as an event for monitors and chat integrations while speakers provide the audible cue.

## Incidents and automation

- `incidents [status]`
- `incident open <severity> <title>`
- `incident update <id> <status> [note]`
- `rules`
- `rule set <id> <topic> <lock|unlock|alarm> <target>`
- `rule run <id>`

Incident and rule state is durable and backed up on each write. Rules can respond to security, player, and incident events with zone locks, unlocks, alarms, announcements, and security changes.

## Doors and access control

Choose the Access Controller installer role to configure redstone doors. Each door has an id, zone, redstone side, and required clearance. Use `doors`, `door <id> lock`, or `door @<zone> unlock`. Door-use requests enforce the authenticated account's clearance.

## Facility map

CookieSecurity does not ship the old nine-floor map. Build the facility map incrementally:

```
room set lobby 0 2 2 12 4 Main Lobby
room set vault 0 20 2 8 4 Vault
map monitor
```

Use `room remove <id>` to remove a room. Map state is durable and available to custom displays through `map.get`.

## Redundant Command Authority

During setup, each authority can be assigned peers, priority, and quorum. Auth/core nodes can list primary and backup authorities and require a quorum. Any reachable authority reporting lockdown wins immediately; if quorum cannot be reached, Auth fails closed. `command.cluster` reports membership, reachability, deterministic leader, and quorum state.

Use an odd number of authorities for a majority quorum. Every authority still requires its own player detector, speaker, physical CL6 presence, normal credential, and separate override credential.
The installer enrolls the node with the primary and then prompts for a fresh one-time code from each configured backup authority.

## Fleet updates

Every standard installer role includes the fleet agent. Updates retain signature verification, per-file SHA-256 verification, staging, health marking, backups, and rollback.

- `fleet status <node>`
- `fleet stage <node> [branch-or-tag]`
- `fleet apply <node>`
- `fleet rollback <node>`

Rollout plans are stored through `fleet.plan`. Applying or rolling back schedules a reboot only after an authenticated request is accepted. Fleet management never exposes a remote shell.

## Permissions

New permission families include `operations.view`, `incidents.view`, `incidents.manage`, `automation.view`, `automation.manage`, `access.view`, `access.use`, `access.manage`, `map.view`, `map.manage`, `announcements.send`, `updates.view`, and `updates.manage`.
