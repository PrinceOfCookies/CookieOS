# CookieSecurity Extension API

Extensions are trusted local Lua modules explicitly listed during Auth/core installation or in `extensions.modules`. They do not download or execute remote code. Network callers can invoke only actions an extension deliberately registers, and `extension.call` requires authorization.

An extension exports `register(api)`:

```lua
local extension = {}

function extension.register(api)
    api.register({
        name = "reactor",
        version = "1.0.0",
        description = "Reactor telemetry integration",
        health = function()
            return peripheral.find("fissionReactorLogicAdapter") ~= nil,
                "waiting for reactor adapter"
        end,
        actions = {
            status = function(data, caller)
                local reactor = peripheral.find("fissionReactorLogicAdapter")
                if not reactor then return nil, "Reactor adapter unavailable" end
                return { temperature = reactor.getTemperature(), caller = caller.source }
            end,
        },
    })
end

return extension
```

The API provides:

- `api.register(definition)` to expose metadata, health, and named actions.
- `api.emit(topic, payload)` to publish an `extension.<topic>` event.
- `api.request(service, payload, timeout)` to use a CookieSecurity service.
- `api.audit(action, details)` for a sanitized audit record.
- `api.config()` for read access to the node configuration.

Use `extensions` to inspect loaded modules and `ext <name> <action> [data]` to invoke an action. Keep extension actions narrow and validate every input. Extensions run with local computer privileges and therefore belong in the trusted computing base.
