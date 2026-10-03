local config = {}

local defaults = {
    version = 3,
    node = nil,
    mode = "client",
    location = "unknown",
    network = {
        channel = 42420,
        replyChannel = 42421,
        ttl = 8,
        discoverySeconds = 15,
        routeSeconds = 45,
        seenSeconds = 180,
        requestTimeout = 3,
        requestRetries = 2,
        requireSigned = false,
        trustedKeys = {},
        maxClockSkewMs = 120000,
        maxPacketBytes = 16384,
        maxSeenPackets = 2048,
        maxRoutes = 256,
        requestRate = 30,
        requestRateWindow = 10,
        trustPath = "/cookieos-data/trust.db",
    },
    transports = {},
    services = {},
    identity = {},
    legacy = { enabled = false },
    auth = {
        dataPath = "/cookieos-data/users.db",
        importPath = "/subterra_users.txt",
        trustedNodes = {},
        seedUsers = {},
        sessionSeconds = 1800,
        passwordRounds = 64,
        maxLoginFailures = 5,
        loginLockSeconds = 30,
        delegates = {},
    },
    audit = {
        dataPath = "/cookieos-data/audit.db",
        maxEntries = 1000,
    },
    playerTracking = {
        dataPath = "/cookieos-data/players.db",
        refreshSeconds = 5,
        maxCachedPlayers = 256,
    },
    events = {
        maxTopics = 128,
        retainedPerTopic = 20,
        subscriptionSeconds = 300,
        maxSubscriptions = 512,
        maxEventBytes = 8192,
        publishers = {},
    },
    personnelDisplay = {
        side = nil,
        textScale = 0.5,
        refreshSeconds = 5,
        filter = "all",
    },
    pairing = {
        authority = false,
        protocol = "cookieos_pairing",
        codeSeconds = 120,
        maxPending = 8,
    },
    update = {
        signingKey = nil,
        statePath = "/cookieos-update/state.db",
        stagePath = "/cookieos-update/staged",
        backupPath = "/cookieos-update/backup",
    },
}

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function merge(target, source)
    for key, value in pairs(source or {}) do
        if type(value) == "table" and type(target[key]) == "table" then
            merge(target[key], value)
        else
            target[key] = clone(value)
        end
    end
    return target
end

local function validate(result)
    if result.version ~= 3 then error("Unsupported CookieOS configuration version", 3) end
    if type(result.node) ~= "string" or result.node == "" then
        error("Configuration must contain a non-empty node name", 3)
    end

    local validModes = { client = true, server = true, relay = true, hybrid = true }
    if not validModes[result.mode] then error("Invalid node mode: " .. tostring(result.mode), 3) end
    if type(result.transports) ~= "table" or #result.transports == 0 then
        error("At least one transport is required", 3)
    end
    if result.network.requestRetries < 0 then error("network.requestRetries cannot be negative", 3) end
    if result.network.seenSeconds * 1000 < result.network.maxClockSkewMs then
        error("network.seenSeconds must cover network.maxClockSkewMs", 3)
    end
    if result.network.maxPacketBytes < 512 then error("network.maxPacketBytes is too small", 3) end
    if result.network.maxSeenPackets < 32 then error("network.maxSeenPackets is too small", 3) end
    if result.network.requireSigned and (type(result.identity.nodeKey) ~= "string" or result.identity.nodeKey == "") then
        error("identity.nodeKey is required when network.requireSigned is true", 3)
    end

    local names = {}
    for index, transport in ipairs(result.transports) do
        if transport.type ~= "modem" then error("Unsupported transport type at index " .. index, 3) end
        if type(transport.side) ~= "string" then error("Transport " .. index .. " requires a side", 3) end
        transport.name = transport.name or transport.side
        if names[transport.name] then error("Duplicate transport name: " .. transport.name, 3) end
        names[transport.name] = true
    end

    local disabledPath = "/cookieos-data/disabled-services.db"
    if fs.exists(disabledPath) then
        local handle = fs.open(disabledPath, "r")
        local disabled = handle and textutils.unserialize(handle.readAll()) or {}
        if handle then handle.close() end
        if type(disabled) == "table" then
            local enabled = {}
            for _, name in ipairs(result.services) do
                if not disabled[name] then table.insert(enabled, name) end
            end
            result.services = enabled
        end
    end

    return result
end

function config.load(path)
    path = path or "/cookieos-node.lua"
    if not fs.exists(path) then error("CookieOS configuration not found: " .. path, 2) end

    local chunk, loadError = loadfile(path)
    if not chunk then error("Cannot load configuration: " .. tostring(loadError), 2) end
    local ok, userConfig = pcall(chunk)
    if not ok then error("Configuration failed: " .. tostring(userConfig), 2) end
    if type(userConfig) ~= "table" then error("Configuration must return a table", 2) end

    return validate(merge(clone(defaults), userConfig))
end

return config
