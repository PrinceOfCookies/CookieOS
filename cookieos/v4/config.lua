local config = {}

local defaults = {
    version = 4,
    mode = "client",
    location = "unknown",
    network = { channel = 42420, replyChannel = 42421, ttl = 8, requestTimeout = 3, requestRetries = 2 },
    identity = { nodeKey = nil, user = nil },
    command = { node = nil, required = true },
    logger = { node = nil, required = false },
    services = {},
    transports = {},
}

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function merge(target, source)
    for key, value in pairs(source or {}) do
        if type(value) == "table" and type(target[key]) == "table" then merge(target[key], value)
        else target[key] = clone(value) end
    end
    return target
end

function config.validate(value)
    if type(value) ~= "table" or value.version ~= 4 then error("CookieOS v4 configuration required", 2) end
    if type(value.node) ~= "string" or value.node == "" then error("A unique node name is required", 2) end
    if value.mode ~= "client" and value.mode ~= "server" and value.mode ~= "relay" and value.mode ~= "hybrid" then error("Invalid node mode", 2) end
    if type(value.transports) ~= "table" or #value.transports == 0 then error("At least one modem transport is required", 2) end
    for index, transport in ipairs(value.transports) do
        if type(transport.side) ~= "string" or transport.side == "" then error("Transport " .. index .. " requires a modem side", 2) end
    end
    if value.command.required and (type(value.command.node) ~= "string" or value.command.node == "") then error("Command Authority node is required", 2) end
    return value
end

function config.load(path)
    path = path or "/cookieos-v4.lua"
    if not fs.exists(path) then error("CookieOS v4 configuration not found: " .. path, 2) end
    local chunk, loadError = loadfile(path)
    if not chunk then error(loadError, 2) end
    local ok, value = pcall(chunk)
    if not ok then error(value, 2) end
    return config.validate(merge(clone(defaults), value))
end

return config
