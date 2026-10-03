package.path = package.path .. ";/?.lua;/?/init.lua"

local files, handlers, refreshTask = {}, {}, nil
fs = {
    getDir = function() return "/cookieos-data" end,
    exists = function(path) return path == "/cookieos-data" or files[path] ~= nil end,
    makeDir = function() end,
    delete = function(path) files[path] = nil end,
    move = function(from, to) files[to], files[from] = files[from], nil end,
    open = function(path, mode)
        if mode == "r" then return nil end
        local value = ""
        return { write = function(chunk) value = value .. chunk end, close = function() files[path] = value end }
    end,
}
textutils = { serialize = function() return "{}" end }
local detector = {
    getOnlinePlayers = function() return { "Alice" } end,
    getPlayerPos = function() return { x = 10, y = 64, z = -5, health = 20, dimension = "minecraft:overworld" } end,
}
peripheral = { find = function(kind) if kind == "player_detector" then return detector end end }
sleep = function() error("stop") end

local context = {
    config = { node = "tracker", playerTracking = { refreshSeconds = 5 } },
    authorize = function() return true end,
    network = { provide = function(_, name, handler) handlers[name] = handler end },
    supervisor = { add = function(_, _, task) refreshTask = task end },
}

local service = require("cookieos.services.player_tracker")
service.register(context)
pcall(refreshTask)

local found, err = handlers["players.lookup"]({ query = "ali", actor = "admin" }, { source = "terminal" })
assert(not err and found.name == "Alice" and found.online)
local listed = handlers["players.list"]({ actor = "admin" }, { source = "terminal" })
assert(listed.total == 1)
local healthy, detail = service.health(context)
assert(healthy and detail:find("1 online"))

print("All 3 player tracker tests passed")
