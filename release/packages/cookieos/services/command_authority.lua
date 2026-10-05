local Sha256 = require("cookieos.crypto.sha256")
local service = {}

service.manifest = {
    name = "command-authority", version = "3.5.0",
    provides = { "command.status", "command.cluster" }, depends = { "node" },
    peripherals = { "speaker" },
}

local function hash(password, credential)
    local value = credential.salt .. ":" .. tostring(password)
    for _ = 1, credential.rounds do value = Sha256.hex(value .. ":" .. credential.salt) end
    return value
end
service._hash = hash

local function readState(path)
    if not fs.exists(path) then return { locked = false, generation = 0 } end
    local handle = fs.open(path, "r")
    local value = handle and textutils.unserialize(handle.readAll())
    if handle then handle.close() end
    return type(value) == "table" and value or { locked = true, generation = 1, reason = "Invalid authority state" }
end

local function writeState(path, state)
    local directory = fs.getDir(path)
    if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
    local handle = assert(fs.open(path .. ".new", "w"))
    handle.write(textutils.serialize(state)); handle.close()
    if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
    if fs.exists(path) then fs.move(path, path .. ".bak") end
    fs.move(path .. ".new", path)
end

function service.register(context)
    local options = context.config.commandAuthority or {}
    if not options.authority then error("command-authority requires commandAuthority.authority = true") end
    if type(options.user) ~= "string" or type(options.credential) ~= "table" or type(options.overrideCredential) ~= "table" then
        error("Command Authority credentials are not configured")
    end
    local detector = peripheral.find("playerDetector") or peripheral.find("player_detector")
    local speakers = { peripheral.find("speaker") }
    if not detector then error("Command Authority requires a player detector") end
    if #speakers == 0 then error("Command Authority requires a speaker") end
    local path = options.statePath or "/cookieos-data/command-authority.db"
    local state = readState(path)

    local function audit(action, fields)
        local handle = fs.open("/cookieos-data/command-audit.log", "a")
        if handle then handle.writeLine(textutils.serialize({ at = os.epoch("utc"), action = action, fields = fields or {} })); handle.close() end
    end

    local function announce(sound, pitch)
        for _, speaker in ipairs(speakers) do pcall(speaker.playSound, sound, 3, pitch or 1) end
    end

    local function failureAlarm()
        for _ = 1, 3 do
            announce("minecraft:block.bell.use", 0.5)
            sleep(0.25)
        end
    end

    local function diagnostic(username)
        local details = { username = username, detector = "unknown", gps = "unknown", configuredPosition = options.position, playerLookups = {} }
        if peripheral.getName and peripheral.getMethods then
            local ok, name = pcall(peripheral.getName, detector)
            if not ok then name = nil end
            details.detector = name or "unnamed"
            if name then
                local methodsOk, methods = pcall(peripheral.getMethods, name)
                if methodsOk and type(methods) == "table" then details.detectorMethods = methods end
            end
        end
        if gps and gps.locate then
            local ok, x, y, z = pcall(gps.locate, 2, false)
            if ok and x then details.gps = { x = x, y = y, z = z } else details.gps = "GPS locate failed: " .. tostring(x) end
        end
        if detector.getOnlinePlayers then
            local ok, players = pcall(detector.getOnlinePlayers)
            if ok and type(players) == "table" then details.onlinePlayers = players else details.onlinePlayersError = tostring(players) end
        end
        if username and detector.getPlayerPos then
            local ok, player = pcall(detector.getPlayerPos, username)
            if ok and type(player) == "table" then details.player = player else details.playerError = tostring(player) end
            details.playerLookups[#details.playerLookups + 1] = tostring(username) .. "=" .. (ok and type(player) or "error")
        end
        return details
    end

    local function diagnosticText(details)
        if options.debug == false then return "" end
        local configured = details.configuredPosition
        local configuredText = type(configured) == "table" and (tostring(configured.x) .. "," .. tostring(configured.y) .. "," .. tostring(configured.z)) or "none"
        local parts = { "[Command debug] detector=" .. tostring(details.detector), "gps=" .. (type(details.gps) == "table" and (details.gps.x .. "," .. details.gps.y .. "," .. details.gps.z) or tostring(details.gps)), "computer=" .. configuredText }
        if details.player then parts[#parts + 1] = "player=" .. tostring(details.player.x) .. "," .. tostring(details.player.y) .. "," .. tostring(details.player.z) .. " dimension=" .. tostring(details.player.dimension or "unknown") end
        if details.playerError then parts[#parts + 1] = "player lookup=" .. details.playerError end
        if details.playerLookups and #details.playerLookups > 0 then parts[#parts + 1] = "lookups=" .. table.concat(details.playerLookups, ",") end
        if details.onlinePlayers then
            local names = {}
            for _, name in ipairs(details.onlinePlayers) do names[#names + 1] = tostring(name) end
            parts[#parts + 1] = "online=" .. table.concat(names, ",")
        end
        return table.concat(parts, " | ")
    end

    local function position()
        if gps and gps.locate then
            local x, y, z = gps.locate(2, false)
            if x then return x, y, z end
        end
        local configured = options.position
        if type(configured) == "table" then return tonumber(configured.x), tonumber(configured.y), tonumber(configured.z) end
    end

    local function nearby(username)
        local x, y, z = position()
        local details = diagnostic(username)
        if not x then return nil, "Command Authority location unavailable (GPS failed and no configured position). " .. diagnosticText(details), details end
        local lookupName = username
        local ok, player = pcall(detector.getPlayerPos, lookupName)
        if (not ok or type(player) ~= "table") and type(details.onlinePlayers) == "table" then
            local candidates = {}
            for _, candidate in ipairs(details.onlinePlayers) do candidates[#candidates + 1] = candidate end
            if #candidates == 0 then for _, candidate in pairs(details.onlinePlayers) do candidates[#candidates + 1] = candidate end end
            for _, candidate in ipairs(candidates) do
                if tostring(candidate):lower() == tostring(username):lower() then
                    lookupName = candidate; ok, player = pcall(detector.getPlayerPos, candidate)
                    details.playerLookups[#details.playerLookups + 1] = tostring(candidate) .. "=" .. (ok and type(player) or "error")
                    break
                end
            end
        end
        if not ok or type(player) ~= "table" then return nil, "Configured CL6 player is listed but its coordinates could not be read from the detector. " .. diagnosticText(details), details end
        details.player = player
        local px, py, pz = tonumber(player.x), tonumber(player.y), tonumber(player.z)
        if not px or not py or not pz then return nil, "Detector returned no usable player coordinates. " .. diagnosticText(details), details end
        local distance = math.sqrt((px - x)^2 + (py - y)^2 + (pz - z)^2)
        if distance > (tonumber(options.radius) or 6) then return nil, string.format("CL6 player is %.1f blocks away (radius %.1f). %s", distance, tonumber(options.radius) or 6, diagnosticText(details)), details end
        return true, distance, details
    end

    local function publish()
        context.network:emit("command.lockdown", {
            locked = state.locked, generation = state.generation, reason = state.reason,
            authority = context.config.node, changedAt = state.changedAt,
        })
    end

    local function lock(reason, claimedUser)
        state = { locked = true, generation = (state.generation or 0) + 1, reason = reason,
            claimedUser = claimedUser, changedAt = os.epoch("utc") }
        writeState(path, state); announce("minecraft:block.bell.use", 0.5); publish()
        audit("command.lockdown", { reason = reason, claimedUser = claimedUser, generation = state.generation })
        context.log.error("GLOBAL LOCKDOWN: " .. tostring(reason))
    end

    context.commandAuthority = {
        status = function() return state end,
        authenticate = function()
            if state.locked then return nil, "Facility is locked down" end
            write("CL6 Minecraft username: "); local username = read()
            write("CL6 password: "); local password = read("*")
            local present, presenceError, details = nearby(username)
            if username ~= options.user or not present or hash(password, options.credential) ~= options.credential.hash then
                local reason = presenceError or "Command Authority authentication failed"
                lock(reason, username); failureAlarm()
                return nil, "Authentication failed; facility lockdown activated. " .. reason, details
            end
            audit("command.login", { user = username, outcome = "allowed", distance = presenceError })
            context.log.info("CL6 physical authentication succeeded for " .. username)
            return true
        end,
        override = function()
            write("CL6 Minecraft username: "); local username = read()
            write("Emergency override password: "); local password = read("*")
            local present, presenceError, details = nearby(username)
            if username ~= options.user or not present or hash(password, options.overrideCredential) ~= options.overrideCredential.hash then
                audit("command.override", { user = username, outcome = "denied", reason = presenceError or "invalid credential" })
                context.log.error("Lockdown override failed for " .. tostring(username) .. ": " .. tostring(presenceError or "invalid credential"))
                failureAlarm(); announce("minecraft:block.note_block.bass", 0.5)
                return nil, "Override rejected. " .. tostring(presenceError or "invalid credential"), details
            end
            state = { locked = false, generation = (state.generation or 0) + 1, changedAt = os.epoch("utc"), clearedBy = username }
            writeState(path, state); announce("minecraft:block.note_block.chime", 1.5); publish()
            audit("command.override", { user = username, outcome = "allowed", generation = state.generation })
            context.log.info("Global lockdown cleared locally by " .. username)
            return true
        end,
        diagnostics = function(username) return diagnostic(username) end,
    }

    context.network:provide("command.status", function()
        return { locked = state.locked, generation = state.generation, reason = state.reason, authority = context.config.node,
            priority = tonumber((context.config.commandCluster or {}).priority) or 100,
            peers = (context.config.commandCluster or {}).peers or {} }
    end)
    context.network:provide("command.cluster", function()
        local cluster = context.config.commandCluster or {}
        local members = {{ node = context.config.node, priority = tonumber(cluster.priority) or 100, online = true }}
        for _, peer in ipairs(cluster.peers or {}) do
            local route = context.network.routes[peer]
            members[#members + 1] = { node = peer, online = route ~= nil, age = route and math.floor(os.clock() - route.seenAt) }
        end
        table.sort(members, function(a, b) return a.node < b.node end)
        local leader
        for _, member in ipairs(members) do if member.online and (not leader or (member.priority or 0) > (leader.priority or 0) or ((member.priority or 0) == (leader.priority or 0) and member.node < leader.node)) then leader = member end end
        return { members = members, leader = leader and leader.node, quorum = tonumber(cluster.quorum) or 1,
            quorate = (function() local n=0 for _,m in ipairs(members)do if m.online then n=n+1 end end return n >= (tonumber(cluster.quorum) or 1) end)() }
    end)
    context.supervisor:add("command-lockdown-beacon", function()
        while true do publish(); sleep(5) end
    end)
end

return service
