local Sha256 = require("cookieos.crypto.sha256")
local service = {}

service.manifest = {
    name = "command-authority", version = "3.5.0",
    provides = { "command.status" }, depends = { "node" },
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
        if not x then return nil, "Command Authority location unavailable (GPS failed and no configured position)" end
        local ok, player = pcall(detector.getPlayerPos, username)
        if not ok or type(player) ~= "table" then return nil, "Configured CL6 player is not visible to the detector" end
        local distance = math.sqrt((player.x - x)^2 + (player.y - y)^2 + (player.z - z)^2)
        if distance > (tonumber(options.radius) or 6) then return nil, string.format("CL6 player is %.1f blocks away", distance) end
        return true, distance
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
            local present, presenceError = nearby(username)
            if username ~= options.user or not present or hash(password, options.credential) ~= options.credential.hash then
                lock(presenceError or "Command Authority authentication failed", username)
                return nil, "Authentication failed; facility lockdown activated"
            end
            audit("command.login", { user = username, outcome = "allowed", distance = presenceError })
            context.log.info("CL6 physical authentication succeeded for " .. username)
            return true
        end,
        override = function()
            write("CL6 Minecraft username: "); local username = read()
            write("Emergency override password: "); local password = read("*")
            local present, presenceError = nearby(username)
            if username ~= options.user or not present or hash(password, options.overrideCredential) ~= options.overrideCredential.hash then
                audit("command.override", { user = username, outcome = "denied", reason = presenceError or "invalid credential" })
                context.log.error("Lockdown override failed for " .. tostring(username) .. ": " .. tostring(presenceError or "invalid credential"))
                announce("minecraft:block.note_block.bass", 0.5)
                return nil, "Override rejected"
            end
            state = { locked = false, generation = (state.generation or 0) + 1, changedAt = os.epoch("utc"), clearedBy = username }
            writeState(path, state); announce("minecraft:block.note_block.chime", 1.5); publish()
            audit("command.override", { user = username, outcome = "allowed", generation = state.generation })
            context.log.info("Global lockdown cleared locally by " .. username)
            return true
        end,
    }

    context.network:provide("command.status", function()
        return { locked = state.locked, generation = state.generation, reason = state.reason, authority = context.config.node }
    end)
    context.supervisor:add("command-lockdown-beacon", function()
        while true do publish(); sleep(5) end
    end)
end

return service
