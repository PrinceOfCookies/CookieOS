local Canonical = require("cookieos.crypto.canonical")
local Sha256 = require("cookieos.crypto.sha256")
local update = {}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do if key ~= "signature" then result[key] = copy(child) end end
    return result
end

local function validPath(path)
    return type(path) == "string" and path:sub(1, 1) == "/" and not path:find("..", 1, true)
        and path ~= "/cookieos-node.lua" and not path:find("^/cookieos%-data/")
end

local function writeFile(path, contents)
    local directory = fs.getDir(path)
    if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
    local handle = fs.open(path, "wb") or fs.open(path, "w")
    if not handle then return nil, "Cannot write " .. path end
    handle.write(contents)
    handle.close()
    return true
end

local function readState(path)
    if not fs.exists(path) then return {} end
    local handle = fs.open(path, "r")
    if not handle then return {} end
    local ok, value = pcall(textutils.unserialize, handle.readAll())
    handle.close()
    return ok and type(value) == "table" and value or {}
end

local function writeState(path, value)
    return writeFile(path, textutils.serialize(value))
end

function update.verifyManifest(manifest, signingKey)
    if type(manifest) ~= "table" or type(manifest.files) ~= "table" or type(manifest.version) ~= "string" then
        return nil, "Invalid release manifest"
    end
    if not signingKey then return nil, "No update signing key configured" end
    if Sha256.hmac(signingKey, Canonical.encode(copy(manifest))) ~= manifest.signature then
        return nil, "Release manifest signature is invalid"
    end
    for _, file in ipairs(manifest.files) do
        if not validPath(file.path) or type(file.sha256) ~= "string" then return nil, "Unsafe release path" end
        if file.source ~= nil and (type(file.source) ~= "string" or file.source:sub(1, 1) == "/" or file.source:find("..", 1, true)) then
            return nil, "Unsafe release source"
        end
        if type(file.source) ~= "string" and type(file.url) ~= "string" then return nil, "Release entry has no source" end
    end
    return true
end

function update.stage(config, manifest, fetch)
    local ok, err = update.verifyManifest(manifest, config.update.signingKey)
    if not ok then return nil, err end
    if fs.exists(config.update.stagePath) then fs.delete(config.update.stagePath) end
    fs.makeDir(config.update.stagePath)
    for _, file in ipairs(manifest.files) do
        local contents, fetchError = fetch(file)
        if not contents then return nil, fetchError or ("Cannot fetch " .. file.path) end
        if Sha256.hex(contents) ~= file.sha256 then return nil, "Hash mismatch for " .. file.path end
        local staged = fs.combine(config.update.stagePath, file.path:sub(2))
        local written, writeError = writeFile(staged, contents)
        if not written then return nil, writeError end
    end
    writeState(config.update.statePath, { status = "staged", version = manifest.version, files = manifest.files, attempts = 0 })
    return true
end

function update.apply(config)
    local state = readState(config.update.statePath)
    if state.status ~= "staged" then return nil, "No staged update" end
    if fs.exists(config.update.backupPath) then fs.delete(config.update.backupPath) end
    fs.makeDir(config.update.backupPath)
    for _, file in ipairs(state.files) do
        local target = file.path
        local staged = fs.combine(config.update.stagePath, target:sub(2))
        local backup = fs.combine(config.update.backupPath, target:sub(2))
        if fs.exists(target) then
            local directory = fs.getDir(backup)
            if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
            fs.copy(target, backup)
        end
        local directory = fs.getDir(target)
        if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
        if fs.exists(target) then fs.delete(target) end
        fs.copy(staged, target)
    end
    state.status, state.appliedAt, state.attempts = "pending", os.epoch("utc"), 0
    writeState(config.update.statePath, state)
    return true
end

function update.rollback(config)
    local state = readState(config.update.statePath)
    if not state.files or not fs.exists(config.update.backupPath) then return nil, "No update backup" end
    for _, file in ipairs(state.files) do
        local target = file.path
        local backup = fs.combine(config.update.backupPath, target:sub(2))
        if fs.exists(target) then fs.delete(target) end
        if fs.exists(backup) then
            local directory = fs.getDir(target)
            if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
            fs.copy(backup, target)
        end
    end
    state.status = "rolled_back"
    writeState(config.update.statePath, state)
    return true
end

function update.beginBoot(config)
    local state = readState(config.update.statePath)
    if state.status == "pending" then
        state.attempts = (state.attempts or 0) + 1
        writeState(config.update.statePath, state)
        return state.attempts <= 2, state
    end
    return true, state
end

function update.markHealthy(config)
    local state = readState(config.update.statePath)
    if state.status == "pending" then state.status = "healthy"; state.healthyAt = os.epoch("utc"); writeState(config.update.statePath, state) end
end

return update
