# CookieOS v3 service manifests

Every service module exports a manifest alongside `register(context)`:

```lua
service.manifest = {
  name = "player-tracker",
  version = "3.1.0",
  provides = { "players.lookup", "players.list" },
  depends = { "auth" },
  peripherals = { "player_detector", { type = "monitor", optional = true } },
}
```

At boot, CookieOS validates unique names, dependencies, and required peripherals.
After registration it verifies that every declared endpoint exists. Invalid service
graphs fail before the network starts instead of producing partially working nodes.

The built-in `service.list` endpoint returns registered versions, dependencies,
endpoints, and optional health-check results. A module may export
`health(context)`, returning `true, "detail"` or `false, "reason"`.
