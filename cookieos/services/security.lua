local service = {}

service.manifest = {
    name = "security", version = "3.1.0",
    provides = { "security.get", "security.set" },
}

function service.register(context)
    local level = "GREEN"
    local valid = { GREEN = true, YELLOW = true, RED = true, BLACK = true }

    local function state()
        return { level = level, node = context.config.node, changedAt = os.epoch("utc") }
    end

    context.network:provide("security.get", function(payload, packet)
        if context.auth or packet then
            local allowed, reason = context.authorize(payload, packet, "security.view")
            if not allowed then return nil, reason end
        end
        return state()
    end)
    context.network:provide("security.set", function(payload, packet)
        if context.auth or packet then
            local allowed, reason = context.authorize(payload, packet, "security.setLevel")
            if not allowed then return nil, reason end
        end
        local requested = tostring(payload and payload.level or ""):upper()
        if not valid[requested] then return nil, "Invalid security level" end
        level = requested
        context.publish("security.changed", { level = level, actor = payload and payload.actor })
        if context.audit then
            context.audit.write("security.level.set", {
                actor = payload and payload.actor or "session",
                details = { level = level, source = packet and packet.source },
            })
        end
        context.network:emit("security.changed", state())
        return state()
    end)

    context.security = {
        get = function() return level end,
        setInternal = function(requested, source)
            requested = tostring(requested or ""):upper()
            if not valid[requested] then return nil, "Invalid security level" end
            level = requested
            context.publish("security.changed", { level = level, actor = source or "internal" })
            context.network:emit("security.changed", state())
            return state()
        end,
    }
end

return service
