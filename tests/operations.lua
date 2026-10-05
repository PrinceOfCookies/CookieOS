package.path = "./?.lua;./?/init.lua;" .. package.path

local files = {}
fs = {
    exists = function(path) return files[path] ~= nil end,
    getDir = function(path) return path:match("^(.*)/[^/]+$") or "" end,
    makeDir = function() end,
    delete = function(path) files[path] = nil end,
    move = function(from, to) files[to], files[from] = files[from], nil end,
    open = function(path, mode)
        local buffer = mode == "a" and (files[path] or "") or ""
        if mode == "r" then
            if files[path] == nil then return nil end
            return { readAll = function() return files[path] end, close = function() end }
        end
        return { write = function(value) buffer = buffer .. value end, close = function() files[path] = buffer end }
    end,
}
textutils = {
    serialize = function(value)
        local function encode(v)
            if type(v) == "table" then local out={"{"}; for k,x in pairs(v) do out[#out+1]="["..encode(k).."]="..encode(x).."," end; out[#out+1]="}"; return table.concat(out) end
            return type(v)=="string" and string.format("%q",v) or tostring(v)
        end
        return encode(value)
    end,
    unserialize = function(value) return assert(load("return " .. value))() end,
}
redstone = { outputs = {}, setOutput = function(side, value) redstone.outputs[side] = value end }

local handlers, emitted = {}, {}
local context = {
    config = { node = "core", mode = "server", location = "HQ", operations = { doors = {
        { id = "vault", zone = "secure", side = "back", clearance = 4, locked = true },
    } }, update = { statePath = "/update.db" } },
    network = {
        routes = { terminal = { mode = "client", location = "Lobby", services = {"terminal"}, seenAt = os.clock(), signed = true } },
        provide = function(_, name, handler) handlers[name] = handler end,
        localServices = function() return { "operations" } end,
        request = function() return { ok = true, data = {} } end,
    },
    authorize = function() return true, "Allowed", { user = "admin", clearance = 5 } end,
    publish = function(topic, payload) emitted[#emitted + 1] = { topic = topic, payload = payload }; return true end,
    audit = { write = function() end },
    log = { error = function() end },
}

require("cookieos.services.operations").register(context)
local packet = { source = "terminal" }
local function call(name, payload)
    local result, err = handlers[name](payload or {}, packet)
    assert(result, err)
    return result
end

local snapshot = call("ops.snapshot")
assert(#snapshot.nodes == 2 and snapshot.openIncidents == 0)
local incident = call("incident.open", { title = "Vault alarm", severity = "high" })
assert(incident.id == "INC-00001" and call("incident.list").total == 1)
assert(call("incident.update", { id = incident.id, status = "closed", note = "Resolved" }).status == "closed")
assert(call("map.room.set", { id = "vault_room", name = "Vault", x = 2, y = 3 }).id == "vault_room")
assert(call("access.set", { id = "vault", locked = false }).changed == 1)
assert(redstone.outputs.back == true)
call("automation.set", { id = "red_lock", topic = "security.changed", actions = {{ type = "lock-zone", zone = "secure" }} })
assert(call("automation.run", { id = "red_lock" }).results[1].changed == 1)
assert(call("fleet.plan", { id = "canary", version = "3.6", nodes = {"terminal"}, batch = 1 }).status == "planned")
print("Operations, incidents, access, map, automation, and fleet tests passed.")
