local service = {}

service.manifest = {
    name = "personnel", version = "3.3.0",
    provides = { "personnel.list", "personnel.search", "personnel.stats" },
    depends = { "auth" },
}

local function contains(value, query)
    return tostring(value or ""):lower():find(tostring(query or ""):lower(), 1, true) ~= nil
end

function service.register(context)
    local function filtered(filter, query)
        filter = tostring(filter or "all"):lower()
        local result = {}
        for _, user in ipairs(context.auth.listUsers()) do
            local include = true
            local role, status = user.role:lower(), user.status:lower()
            if filter == "fired" then
                include = status == "fired"
            elseif filter == "visitors" or filter == "visitor" then
                include = role:find("visitor", 1, true) ~= nil
            elseif filter:match("^cl%d$") then
                include = user.clearanceLabel:lower() == filter
            elseif filter == "active" then
                include = status == "active"
            end
            if include and query and query ~= "" then
                include = contains(user.name, query) or contains(user.role, query)
                    or contains(user.status, query) or contains(user.clearanceLabel, query)
            end
            if include then table.insert(result, user) end
        end
        return result
    end

    context.personnel = { list = filtered }

    context.network:provide("personnel.list", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "personnel.view")
        if not allowed then return nil, reason end
        local result = filtered(payload.filter, payload.query)
        return { users = result, total = #result, filter = payload.filter or "all" }
    end)

    context.network:provide("personnel.search", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "personnel.view")
        if not allowed then return nil, reason end
        local result = filtered("all", payload.query)
        return { users = result, total = #result, query = payload.query }
    end)

    context.network:provide("personnel.stats", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "personnel.view")
        if not allowed then return nil, reason end
        return {
            total = #filtered("all"), active = #filtered("active"), fired = #filtered("fired"),
            visitors = #filtered("visitors"),
        }
    end)

    context.publish("personnel.ready", { total = #filtered("all") })
end

return service
