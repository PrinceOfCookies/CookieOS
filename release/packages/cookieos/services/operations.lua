local service = {}

service.manifest = {
    name = "operations", version = "3.6.0",
    provides = {
        "ops.snapshot", "incident.list", "incident.open", "incident.update",
        "automation.list", "automation.set", "automation.remove", "automation.run",
        "access.list", "access.set", "access.request",
        "map.get", "map.room.set", "map.room.remove",
        "fleet.status", "fleet.plan", "fleet.command",
    },
    depends = { "node" },
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function readTable(path, fallback)
    if not fs.exists(path) then return copy(fallback) end
    local handle = fs.open(path, "r")
    if not handle then return copy(fallback) end
    local ok, value = pcall(textutils.unserialize, handle.readAll())
    handle.close()
    return ok and type(value) == "table" and value or copy(fallback)
end

local function writeTable(path, value)
    local directory = fs.getDir(path)
    if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
    local temporary = path .. ".tmp"
    local handle = fs.open(temporary, "w")
    if not handle then return nil, "Cannot write " .. path end
    handle.write(textutils.serialize(value))
    handle.close()
    if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
    if fs.exists(path) then fs.move(path, path .. ".bak") end
    fs.move(temporary, path)
    return true
end

local function count(values)
    local result = 0
    for _ in pairs(values or {}) do result = result + 1 end
    return result
end

local function cleanId(value)
    value = tostring(value or "")
    if #value < 1 or #value > 40 or not value:match("^[%w_%-]+$") then return nil end
    return value
end

function service.register(context)
    local options = context.config.operations or {}
    local dataPath = options.dataPath or "/cookieos-data/operations.db"
    local state = readTable(dataPath, {
        sequence = 0, incidents = {}, rules = {}, rooms = {}, doors = {}, fleet = { plans = {} },
    })
    state.incidents, state.rules, state.rooms = state.incidents or {}, state.rules or {}, state.rooms or {}
    state.doors, state.fleet = state.doors or {}, state.fleet or { plans = {} }
    state.fleet.plans = state.fleet.plans or {}
    local doorConfig = options.doors or {}
    for _, door in ipairs(doorConfig) do
        if cleanId(door.id) then
            state.doors[door.id] = state.doors[door.id] or {
                id = door.id, zone = door.zone or "default", side = door.side,
                clearance = math.max(0, math.min(5, tonumber(door.clearance) or 1)), locked = door.locked ~= false,
            }
        end
    end

    local function save() return writeTable(dataPath, state) end
    local function authorize(payload, packet, permission)
        local allowed, reason, identity = context.authorize(payload, packet, permission)
        if not allowed then return nil, reason end
        return identity or true
    end
    local function audit(action, payload, packet, details)
        if context.audit then context.audit.write(action, {
            actor = payload and payload.actor or "session", details = details,
            source = packet and packet.source,
        }) end
    end
    local function emit(topic, payload)
        context.publish(topic, payload)
    end
    local function setDoor(door, locked)
        door.locked = locked == true
        door.changedAt = os.epoch("utc")
        if door.side and redstone and redstone.setOutput then
            -- A powered output means unlocked by default; invert may be configured per door.
            local output = door.locked == (door.invert == true)
            redstone.setOutput(door.side, output)
        end
    end

    local function runActions(actions, source)
        local results = {}
        for _, action in ipairs(actions or {}) do
            local kind = tostring(action.type or "")
            if kind == "security" and context.security then
                local changed, err = context.security.setInternal(action.level, "automation:" .. tostring(source))
                results[#results + 1] = { type = kind, accepted = changed ~= nil, level = action.level, error = err }
            elseif kind == "lock-zone" or kind == "unlock-zone" then
                local locked = kind == "lock-zone"
                local changed = 0
                for _, door in pairs(state.doors) do
                    if action.zone == "all" or door.zone == action.zone then setDoor(door, locked); changed = changed + 1 end
                end
                results[#results + 1] = { type = kind, changed = changed }
            elseif kind == "sound" then
                context.network:request("audio.sound", { sound = action.sound, actor = "automation:" .. tostring(source) })
                results[#results + 1] = { type = kind, accepted = true }
            elseif kind == "alarm" then
                context.network:request("audio.alarm", { count = action.count, actor = "automation:" .. tostring(source) })
                results[#results + 1] = { type = kind, accepted = true }
            elseif kind == "announce" then
                context.network:request("audio.announce", { message = action.message, priority = action.priority, actor = "automation:" .. tostring(source) })
                results[#results + 1] = { type = kind, accepted = true }
            end
        end
        save()
        return results
    end

    local function trigger(topic, event)
        for id, rule in pairs(state.rules) do
            if rule.enabled ~= false and rule.topic == topic then
                local results = runActions(rule.actions, id)
                rule.lastRun = os.epoch("utc")
                emit("automation.ran", { rule = id, topic = topic, results = results, event = event })
            end
        end
        save()
    end
    if context.events then
        for _, topic in ipairs({ "security.changed", "player.online", "player.offline", "incident.opened" }) do
            context.events.on(topic, function(event) trigger(topic, event) end)
        end
    end

    context.network:provide("ops.snapshot", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "operations.view")
        if not allowed then return nil, reason end
        local nodes = {{ node = context.config.node, mode = context.config.mode, location = context.config.location,
            services = context.network:localServices(), age = 0, localNode = true }}
        for name, route in pairs(context.network.routes) do
            nodes[#nodes + 1] = { node = name, mode = route.mode, location = route.location,
                services = route.services, age = math.floor(os.clock() - route.seenAt), failures = route.failures or 0,
                signed = route.signed == true }
        end
        table.sort(nodes, function(a, b) return a.node < b.node end)
        return { node = context.config.node, generatedAt = os.epoch("utc"), nodes = nodes,
            incidents = count(state.incidents), openIncidents = (function() local n=0 for _,v in pairs(state.incidents)do if v.status~="closed"then n=n+1 end end return n end)(),
            doors = copy(state.doors), rooms = count(state.rooms), rules = count(state.rules), fleetPlans = count(state.fleet.plans) }
    end)

    context.network:provide("incident.list", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "incidents.view")
        if not allowed then return nil, reason end
        local result = {}
        for _, incident in pairs(state.incidents) do
            if not payload.status or incident.status == payload.status then result[#result + 1] = copy(incident) end
        end
        table.sort(result, function(a, b) return a.id > b.id end)
        return { incidents = result, total = #result }
    end)
    context.network:provide("incident.open", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "incidents.manage")
        if not allowed then return nil, reason end
        state.sequence = (state.sequence or 0) + 1
        local id = string.format("INC-%05d", state.sequence)
        state.incidents[id] = { id = id, title = tostring(payload.title or "Untitled incident"),
            severity = tostring(payload.severity or "medium"):lower(), status = "open", zone = payload.zone,
            owner = payload.owner, notes = {}, openedAt = os.epoch("utc"), source = packet.source }
        save(); audit("incident.open", payload, packet, state.incidents[id]); emit("incident.opened", copy(state.incidents[id]))
        return copy(state.incidents[id])
    end)
    context.network:provide("incident.update", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "incidents.manage")
        if not allowed then return nil, reason end
        local incident = state.incidents[tostring(payload.id or "")]
        if not incident then return nil, "Incident not found" end
        if payload.status then incident.status = tostring(payload.status):lower() end
        if payload.owner then incident.owner = tostring(payload.owner) end
        if payload.note then incident.notes[#incident.notes + 1] = { at = os.epoch("utc"), text = tostring(payload.note), source = packet.source } end
        incident.updatedAt = os.epoch("utc"); save(); audit("incident.update", payload, packet, { id = incident.id, status = incident.status })
        emit("incident.updated", copy(incident)); return copy(incident)
    end)

    context.network:provide("automation.list", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "automation.view"); if not allowed then return nil, reason end
        return { rules = copy(state.rules) }
    end)
    context.network:provide("automation.set", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "automation.manage"); if not allowed then return nil, reason end
        local id = cleanId(payload.id); if not id then return nil, "Invalid rule id" end
        if type(payload.topic) ~= "string" or type(payload.actions) ~= "table" then return nil, "Rule requires topic and actions" end
        state.rules[id] = { id = id, topic = payload.topic, actions = copy(payload.actions), enabled = payload.enabled ~= false,
            updatedAt = os.epoch("utc") }; save(); audit("automation.set", payload, packet, { id = id }); return copy(state.rules[id])
    end)
    context.network:provide("automation.remove", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "automation.manage"); if not allowed then return nil, reason end
        local id = cleanId(payload.id); if not id or not state.rules[id] then return nil, "Rule not found" end
        state.rules[id] = nil; save(); audit("automation.remove", payload, packet, { id = id }); return { removed = id }
    end)
    context.network:provide("automation.run", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "automation.manage"); if not allowed then return nil, reason end
        local rule = state.rules[tostring(payload.id or "")]; if not rule then return nil, "Rule not found" end
        local results = runActions(rule.actions, rule.id); rule.lastRun = os.epoch("utc"); save(); return { rule = rule.id, results = results }
    end)

    context.network:provide("access.list", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "access.view"); if not allowed then return nil, reason end
        return { doors = copy(state.doors) }
    end)
    context.network:provide("access.set", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "access.manage"); if not allowed then return nil, reason end
        local changed = 0
        for _, door in pairs(state.doors) do
            if payload.id == door.id or payload.zone == "all" or payload.zone == door.zone then setDoor(door, payload.locked); changed = changed + 1 end
        end
        if changed == 0 then return nil, "No matching doors" end
        save(); audit("access.set", payload, packet, { changed = changed, locked = payload.locked }); emit("access.changed", { changed = changed, locked = payload.locked })
        return { changed = changed, locked = payload.locked == true }
    end)
    context.network:provide("access.request", function(payload, packet)
        local identity, reason = authorize(payload, packet, "access.use"); if not identity then return nil, reason end
        local door = state.doors[tostring(payload.id or "")]; if not door then return nil, "Door not found" end
        local clearance = type(identity) == "table" and tonumber(identity.clearance) or 0
        if clearance < (door.clearance or 1) then return nil, "Insufficient clearance for this door" end
        setDoor(door, false); save(); audit("access.granted", payload, packet, { id = door.id }); emit("access.granted", { id = door.id, zone = door.zone })
        return { granted = true, door = copy(door) }
    end)

    context.network:provide("map.get", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "map.view"); if not allowed then return nil, reason end
        return { rooms = copy(state.rooms) }
    end)
    context.network:provide("map.room.set", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "map.manage"); if not allowed then return nil, reason end
        local id = cleanId(payload.id); if not id then return nil, "Invalid room id" end
        state.rooms[id] = { id = id, name = tostring(payload.name or id), floor = tonumber(payload.floor) or 0,
            x = tonumber(payload.x) or 1, y = tonumber(payload.y) or 1, width = math.max(1, tonumber(payload.width) or 5),
            height = math.max(1, tonumber(payload.height) or 3), zone = tostring(payload.zone or "default"), color = tonumber(payload.color) }
        save(); audit("map.room.set", payload, packet, { id = id }); emit("map.changed", { id = id }); return copy(state.rooms[id])
    end)
    context.network:provide("map.room.remove", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "map.manage"); if not allowed then return nil, reason end
        local id = cleanId(payload.id); if not id or not state.rooms[id] then return nil, "Room not found" end
        state.rooms[id] = nil; save(); audit("map.room.remove", payload, packet, { id = id }); emit("map.changed", { id = id, removed = true }); return { removed = id }
    end)

    context.network:provide("fleet.status", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "updates.view"); if not allowed then return nil, reason end
        return { node = context.config.node, version = context.config.releaseVersion or "unknown", plans = copy(state.fleet.plans),
            update = readTable((context.config.update or {}).statePath or "/cookieos-update/state.db", {}) }
    end)
    context.network:provide("fleet.plan", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "updates.manage"); if not allowed then return nil, reason end
        local id = cleanId(payload.id); if not id then return nil, "Invalid rollout id" end
        state.fleet.plans[id] = { id = id, version = tostring(payload.version or ""), nodes = copy(payload.nodes or {}),
            batch = math.max(1, tonumber(payload.batch) or 1), status = "planned", createdAt = os.epoch("utc") }
        save(); audit("fleet.plan", payload, packet, { id = id }); return copy(state.fleet.plans[id])
    end)
    context.network:provide("fleet.command", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "updates.manage"); if not allowed then return nil, reason end
        local action = tostring(payload.action or "")
        if action ~= "stage" and action ~= "apply" and action ~= "rollback" and action ~= "health" then return nil, "Invalid fleet action" end
        emit("fleet.command", { action = action, plan = payload.plan, node = payload.node, source = packet.source })
        audit("fleet.command", payload, packet, { action = action, plan = payload.plan }); return { accepted = true, action = action }
    end)

    context.operations = { state = state, snapshot = function() return { incidents = count(state.incidents), doors = count(state.doors), rooms = count(state.rooms) } end }
end

function service.health(context)
    return context.operations ~= nil, context.operations and "operational" or "not initialized"
end

return service
