# CookieOS v3 operations

## Resource controls

The network runtime bounds packet size, replay-cache size, route count, and requests
per source. Defaults are suitable for a small facility and can be adjusted under
`network` with `maxPacketBytes`, `maxSeenPackets`, `maxRoutes`, `requestRate`, and
`requestRateWindow`. The replay cache must cover the complete accepted clock-skew
window, which configuration validation enforces.

## Audit service

Add `auth` and `audit` to the central server. Audit data is stored at
`/cookieos-data/audit.db`, keeps a backup during replacement, and is bounded by
`audit.maxEntries`. Credentials, proofs, sessions, and tokens are removed from
details before persistence. Use `audit [limit]` from an authorized terminal.

## Delegated authorization

Peripheral servers do not need copies of the user database. Add their signed node
names to the authority's `auth.delegates` table. A service forwards the session token,
original signed source, and requested permission to `auth.authorize`; the authority
verifies that the session belongs to that original source.

```lua
auth = {
  delegates = {
    ["player-tracker-01"] = true,
  },
}
```

Only delegate signed nodes. Delegation over an unsigned network is vulnerable to
node-name impersonation.

## Player tracker and maintenance

The `player-tracker` service requires a `player_detector`, periodically saves a
bounded location cache, and exposes `players.lookup`, `players.list`, and
`players.cache.count`. The `maintenance` service exposes local health, discovered
nodes, routes, and service health. Terminal commands include `where`, `maint`,
`nodes`, and `audit`.
