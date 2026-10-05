package.path = package.path .. ";/?.lua;/?/init.lua"

local files, openWrites, emitted, provided = {}, {}, {}, {}
fs = {
    exists = function(path) return files[path] ~= nil end,
    getDir = function() return "/cookieos-data" end,
    makeDir = function() end,
    delete = function(path) files[path] = nil end,
    move = function(from, to) files[to], files[from] = files[from], nil end,
    open = function(path, mode)
        if mode == "w" then
            return { write = function(value) openWrites[path] = value end, writeLine = function(value) openWrites[path] = value end,
                close = function() files[path] = openWrites[path] end }
        end
        if mode == "a" then return { writeLine = function(value) files[path] = (files[path] or "") .. tostring(value) end, close = function() end } end
        if not files[path] then return nil end
        return { readAll = function() return files[path] end, close = function() end }
    end,
}
textutils = {
    serialize = function(value) return value end,
    unserialize = function(value) return value end,
}
local speaker = { playSound = function() end }
local detector = { getPlayerPos = function(name) if name == "Owner" then return { x = 10, y = 64, z = 10 } end end }
peripheral = { find = function(kind) if kind == "speaker" then return speaker elseif kind == "playerDetector" then return detector end end }
gps = { locate = function() return 10, 64, 10 end }
sleep = function() end
local input = {}
read = function() local value = table.remove(input, 1); return value end
write = function() end

local Command = require("cookieos.services.command_authority")
local normal = { salt = "normal", rounds = 2 }
normal.hash = Command._hash("correct-password", normal)
local override = { salt = "override", rounds = 2 }
override.hash = Command._hash("override-password", override)
local context = {
    config = { node = "command", location = "HQ", identity = { nodeKey = "key" }, commandAuthority = {
        authority = true, user = "Owner", radius = 6, statePath = "/cookieos-data/command.db",
        credential = normal, overrideCredential = override,
    } },
    supervisor = { add = function() end },
    network = {
        provide = function(_, name, handler) provided[name] = handler end,
        emit = function(_, name, payload) emitted[#emitted + 1] = { name = name, payload = payload } end,
    },
    log = { info = function() end, error = function() end },
}
Command.register(context)
input = { "Owner", "correct-password" }
assert(context.commandAuthority.authenticate())
input = { "Owner", "wrong-password" }
assert(context.commandAuthority.authenticate() == nil)
assert(provided["command.status"]().locked == true)
input = { "Owner", "override-password" }
assert(context.commandAuthority.override())
assert(provided["command.status"]().locked == false)
assert(#emitted >= 2)
print("Command Authority authentication and lockdown tests passed")
