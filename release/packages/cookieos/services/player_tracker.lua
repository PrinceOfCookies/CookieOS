local service = {}

service.manifest = {
    name = "player-tracker", version = "3.2.0",
    provides = { "players.lookup", "players.list", "players.cache.count" },
    depends = {},
    peripherals = { "player_detector" },
}

local function normalize(value) return tostring(value or ""):lower() end

function service.register(context)
    local options = context.config.playerTracking or {}
    local path = options.dataPath or "/cookieos-data/players.db"
    local detector = peripheral.find("player_detector")
    local cache, online = {}, {}
    local lastRefresh, lastError = 0, nil

    local function save()
        local directory = fs.getDir(path)
        if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
        local temporary, backup = path .. ".new", path .. ".bak"
        local handle = fs.open(temporary, "w")
        if not handle then return end
        handle.write(textutils.serialize({ version = 1, players = cache }))
        handle.close()
        if fs.exists(backup) then fs.delete(backup) end
        if fs.exists(path) then fs.move(path, backup) end
        local ok, err = pcall(fs.move, temporary, path)
        if not ok then
            if fs.exists(backup) and not fs.exists(path) then fs.move(backup, path) end
            lastError = tostring(err)
            return nil, lastError
        end
        return true
    end

    local function load()
        if not fs.exists(path) then return end
        local handle = fs.open(path, "r")
        if not handle then return end
        local ok, data = pcall(textutils.unserialize, handle.readAll())
        handle.close()
        if ok and type(data) == "table" then cache = data.players or data end
    end

    local function snapshot(name, position)
        return {
            name = name, x = position.x, y = position.y, z = position.z,
            health = position.health, dimension = position.dimension,
            online = true, lastSeen = os.epoch("utc"),
        }
    end

    local function refresh()
        local ok, names = pcall(detector.getOnlinePlayers)
        if not ok or type(names) ~= "table" then lastError = tostring(names); return end
        local previousOnline = online
        online = {}
        for _, name in ipairs(names) do
            local positionOk, position = pcall(detector.getPlayerPos, name)
            if positionOk and type(position) == "table" then
                local record = snapshot(name, position)
                online[name], cache[name] = record, record
            end
        end
        local count = 0
        for _ in pairs(cache) do count = count + 1 end
        while count > (options.maxCachedPlayers or 256) do
            local oldestName, oldestTime
            for name, record in pairs(cache) do
                if not online[name] and (not oldestTime or (record.lastSeen or 0) < oldestTime) then
                    oldestName, oldestTime = name, record.lastSeen or 0
                end
            end
            if not oldestName then break end
            cache[oldestName], count = nil, count - 1
        end
        lastRefresh, lastError = os.epoch("utc"), nil
        save()
        for name, record in pairs(online) do
            if not previousOnline[name] then context.publish("player.online", record) end
        end
        for name, record in pairs(previousOnline) do
            if not online[name] then
                context.publish("player.offline", { name = name, lastSeen = record.lastSeen, dimension = record.dimension })
            end
        end
    end

    local function authorize(payload, packet, permission)
        local allowed, reason = context.authorize(payload, packet, permission)
        if not allowed then return nil, reason end
        return true
    end

    local function find(query)
        query = normalize(query)
        local best, bestScore
        for name, record in pairs(cache) do
            local at = normalize(name):find(query, 1, true)
            if at then
                local score = at + math.abs(#name - #query) + (online[name] and 0 or 100)
                if not bestScore or score < bestScore then best, bestScore = record, score end
            end
        end
        return best
    end

    load()
    context.playerTracker = {
        status = function()
            local onlineCount, cachedCount = 0, 0
            for _ in pairs(online) do onlineCount = onlineCount + 1 end
            for _ in pairs(cache) do cachedCount = cachedCount + 1 end
            return { online = onlineCount, cached = cachedCount, lastRefresh = lastRefresh, error = lastError }
        end,
    }

    context.network:provide("players.lookup", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "players.where")
        if not allowed then return nil, reason end
        local query = payload and (payload.query or payload.player)
        if not query or query == "" then return nil, "Player name is required" end
        local record = find(query)
        if not record then return nil, "No online or cached player matches " .. tostring(query) end
        local result = {}
        for key, value in pairs(record) do result[key] = value end
        result.online = online[result.name] ~= nil
        if context.audit then
            context.audit.write("players.lookup", {
                actor = payload.actor or "session", node = packet.source,
                details = { query = query, result = result.name },
            })
        end
        return result
    end)

    context.network:provide("players.list", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "players.cache")
        if not allowed then return nil, reason end
        local result = {}
        for name, record in pairs(online) do table.insert(result, record) end
        table.sort(result, function(a, b) return normalize(a.name) < normalize(b.name) end)
        return { players = result, total = #result, refreshedAt = lastRefresh }
    end)

    context.network:provide("players.cache.count", function(payload, packet)
        local allowed, reason = authorize(payload, packet, "players.cache")
        if not allowed then return nil, reason end
        return context.playerTracker.status()
    end)

    context.supervisor:add("player-tracker.refresh", function()
        while true do
            refresh()
            sleep(options.refreshSeconds or 5)
        end
    end)
end

function service.health(context)
    if not context.playerTracker then return false, "not initialized" end
    local status = context.playerTracker.status()
    return status.error == nil, status.error or (status.online .. " online, " .. status.cached .. " cached")
end

return service
