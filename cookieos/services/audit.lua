local service = {}

service.manifest = {
    name = "audit", version = "3.2.0",
    provides = { "audit.append", "audit.query", "audit.stats" },
    depends = { "auth" },
}

local function copy(value, depth)
    if type(value) ~= "table" then return value end
    if depth <= 0 then return "<nested>" end
    local result = {}
    for key, child in pairs(value) do
        if key ~= "password" and key ~= "proof" and key ~= "session" and key ~= "token" then
            result[key] = copy(child, depth - 1)
        end
    end
    return result
end

function service.register(context)
    local options = context.config.audit or {}
    local path = options.dataPath or "/cookieos-data/audit.db"
    local maxEntries = options.maxEntries or 1000
    local records = {}
    local sequence = 0

    local function save()
        local directory = fs.getDir(path)
        if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
        local temporary, backup = path .. ".new", path .. ".bak"
        local handle = fs.open(temporary, "w")
        if not handle then return nil, "Cannot write audit database" end
        handle.write(textutils.serialize({ version = 1, sequence = sequence, records = records }))
        handle.close()
        if fs.exists(backup) then fs.delete(backup) end
        if fs.exists(path) then fs.move(path, backup) end
        local ok, err = pcall(fs.move, temporary, path)
        if not ok then
            if fs.exists(backup) and not fs.exists(path) then fs.move(backup, path) end
            return nil, tostring(err)
        end
        return true
    end

    local function load()
        if not fs.exists(path) then return end
        local handle = fs.open(path, "r")
        if not handle then return end
        local ok, data = pcall(textutils.unserialize, handle.readAll())
        handle.close()
        if ok and type(data) == "table" then
            records = type(data.records) == "table" and data.records or {}
            sequence = tonumber(data.sequence) or #records
        end
    end

    local function write(action, fields)
        fields = fields or {}
        sequence = sequence + 1
        local record = {
            id = sequence,
            at = os.epoch("utc"),
            node = fields.node or context.config.node,
            actor = fields.actor or "system",
            action = tostring(action),
            outcome = fields.outcome or "success",
            details = copy(fields.details or {}, 3),
        }
        table.insert(records, record)
        while #records > maxEntries do table.remove(records, 1) end
        local ok, err = save()
        if not ok then context.log.error("Audit persistence failed: " .. tostring(err)) end
        return record
    end

    load()
    context.audit = { write = write }

    context.network:provide("audit.append", function(payload, packet)
        local allowed, reason = context.auth.authorizeRequest(payload, packet, "audit.write")
        if not allowed then return nil, reason end
        return write(payload.action or "remote.event", {
            node = packet.source, actor = payload.actor, outcome = payload.outcome, details = payload.details,
        })
    end)

    context.network:provide("audit.query", function(payload, packet)
        local allowed, reason = context.auth.authorizeRequest(payload, packet, "audit.view")
        if not allowed then return nil, reason end
        local limit = math.max(1, math.min(tonumber(payload.limit) or 50, 200))
        local result = {}
        for index = #records, 1, -1 do
            local record = records[index]
            local matches = (not payload.action or record.action == payload.action)
                and (not payload.actor or record.actor == payload.actor)
                and (not payload.node or record.node == payload.node)
            if matches then table.insert(result, record) end
            if #result >= limit then break end
        end
        return { records = result, total = #records }
    end)

    context.network:provide("audit.stats", function(payload, packet)
        local allowed, reason = context.auth.authorizeRequest(payload, packet, "audit.view")
        if not allowed then return nil, reason end
        return { entries = #records, sequence = sequence, maximum = maxEntries }
    end)

    write("audit.started", { details = { loaded = #records } })
end

function service.health(context)
    return context.audit ~= nil, context.audit and "recording" or "not initialized"
end

return service
