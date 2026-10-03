local service = {}

service.manifest = {
    name = "node", version = "3.1.0",
    provides = { "node.status", "node.ping", "service.list" },
}

function service.register(context)
    local startedAt = os.clock()

    context.network:provide("node.status", function()
        local routes = {}
        for name, route in pairs(context.network.routes) do
            table.insert(routes, {
                node = name,
                mode = route.mode,
                location = route.location,
                services = route.services,
                age = math.floor(os.clock() - route.seenAt),
            })
        end
        table.sort(routes, function(a, b) return a.node < b.node end)

        return {
            node = context.config.node,
            mode = context.config.mode,
            location = context.config.location,
            uptime = math.floor(os.clock() - startedAt),
            services = context.network:localServices(),
            routes = routes,
        }
    end)

    context.network:provide("node.ping", function(payload)
        return { pong = true, echo = payload, node = context.config.node }
    end)

    context.network:provide("service.list", function()
        local result = {}
        for name, registration in pairs(context.registry) do
            local healthy, detail = true, "registered"
            if registration.health then
                local ok, value, message = pcall(registration.health, context)
                healthy, detail = ok and value ~= false, ok and (message or "healthy") or tostring(value)
            end
            table.insert(result, {
                name = name, version = registration.version, provides = registration.provides,
                depends = registration.depends, healthy = healthy, detail = detail,
            })
        end
        table.sort(result, function(a, b) return a.name < b.name end)
        return { services = result }
    end)
end

return service
