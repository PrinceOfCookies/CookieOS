# CookieOS v3 architecture

CookieOS v3 is a distributed ComputerCraft runtime. A computer is configured as a
client, server, relay, or hybrid node; applications are no longer coupled to a
specific computer ID or modem side.

## Node modes

| Mode | Runs services | Makes requests | Relays traffic |
| --- | --- | --- | --- |
| `client` | optional local services | yes | no |
| `server` | yes | yes | no |
| `relay` | optional diagnostics | yes | yes |
| `hybrid` | yes | yes | yes |

A relay retransmits through every configured modem, including the ingress modem.
The packet ID cache and TTL prevent routing loops.

## Packet envelope

Every native packet is a Lua table with these fields:

```lua
{
  cookieos = 3,
  id = "node:epoch:computer:sequence",
  kind = "request", -- request, response, discovery, or event
  source = "terminal-01",
  destination = "auth-01", -- optional for broadcasts
  service = "auth.check",
  replyTo = nil,
  ttl = 8,
  sentAt = 1730000000000,
  payload = {},
  signature = "...", -- present on signed networks
}
```

Only the network runtime reads modem events. It correlates responses by packet ID,
dispatches requests to registered services, tracks discovery advertisements, and
forwards eligible packets on relay and hybrid nodes.

## Signed networks

Set a unique `identity.nodeKey` on every node, distribute the corresponding keys in
`network.trustedKeys`, and enable `network.requireSigned`. Packets use HMAC-SHA-256
over a deterministic encoding. Receivers reject unknown sources, altered packets,
replayed packet IDs, timestamps outside `maxClockSkewMs`, and excessive TTL values.

TTL is deliberately excluded from the signature because relays decrement it. Each
receiver clamps it to the configured network maximum, while all application and
routing fields remain signed.

```lua
identity = { nodeKey = "replace-with-a-long-random-key-for-this-node" },
network = {
  requireSigned = true,
  trustedKeys = {
    ["auth-server-01"] = "the-auth-server-key",
    ["command-terminal-01"] = "the-terminal-key",
  },
}
```

Keys are configured out of band. Do not commit production keys.

## Files

- `startup-v3.lua` is the opt-in entry point.
- `cookieos-node.lua` is a machine's local configuration.
- `cookieos/runtime.lua` assembles the node.
- `cookieos/net/` owns all native networking.
- `cookieos/services/` contains independently registered services.

## Service contract

A service module exports `register(context)` and registers one or more handlers:

```lua
local service = {}

function service.register(context)
  context.network:provide("example.echo", function(payload, request)
    return { value = payload.value, servedBy = context.config.node }
  end)
end

return service
```

Returning `nil, "reason"` produces an unsuccessful response. Throwing an error is
caught at the network boundary and also becomes an unsuccessful response.

## Migration sequence

1. Install an authority node using `examples/nodes/auth-server.lua`.
2. Pair terminal, relay, tracker, and display nodes with the authority.
3. Verify discovery, `node.ping`, and security state.
4. Configure personnel, tracking, maintenance, and display services.
5. Retire the old computers after their replacement nodes report healthy.
