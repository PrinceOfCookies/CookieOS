local service = {}

service.manifest = {
    name = "maintenance", version = "3.2.0",
    provides = { "maintenance.status", "maintenance.nodes", "maintenance.routes", "maintenance.services" },
    depends = { "node" },
}

local function count(values)
    local result = 0
    for _ in pairs(values or {}) do result = result + 1 end
    return result
end

function service.register(context)
    local function authorize(payload, packet, permission)
        local allowed, reason = context.authorize(payload, packet, permission)
        if not allowed then return nil, reason end
        return true
    end

    local function nodes()
        local result = {{
            node = context.config.node, mode = context.config.mode,
            location = context.config.location, age = 0, localNode = true,
            services = context.network:localServices(),
        }}
        for name, route in pairs(context.network.routes) do
            table.insert(result, {
                node = name, mode = route.mode, location = route.location,
                age = math.floor(os.clock() - route.seenAt), failures = route.failures or 0,
                services = route.services, signed = route.signed,
            })
        end
        table.sort(result, function(a, b) return a.node < b.node end)
        return result
    end

    context.network:provide("maintenance.status", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "maintenance.status")
        if not allowed then return nil, reason end
        return {
            node = context.config.node,
            mode = context.config.mode,
            location = context.config.location,
            uptime = math.floor(os.clock()),
            routes = count(context.network.routes),
            seenPackets = count(context.network.seen),
            services = count(context.registry),
            playerTracker = context.playerTracker and context.playerTracker.status() or nil,
        }
    end)

    context.network:provide("maintenance.nodes", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "maintenance.nodes")
        if not allowed then return nil, reason end
        local result = nodes()
        return { nodes = result, total = #result }
    end)

    context.network:provide("maintenance.routes", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "maintenance.nodes")
        if not allowed then return nil, reason end
        return { routes = nodes(), total = count(context.network.routes) }
    end)

    context.network:provide("maintenance.services", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "maintenance.services")
        if not allowed then return nil, reason end
        local result = {}
        for name, registration in pairs(context.registry) do
            local healthy, detail = true, "registered"
            if registration.health then
                local ok, value, message = pcall(registration.health, context)
                healthy, detail = ok and value ~= false, ok and (message or "healthy") or tostring(value)
            end
            table.insert(result, {
                name = name, version = registration.version, healthy = healthy,
                detail = detail, provides = registration.provides,
            })
        end
        table.sort(result, function(a, b) return a.name < b.name end)
        return { services = result, total = #result }
    end)
end

return service
