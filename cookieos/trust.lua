local trust = {}

local function loadData(path)
    if not fs.exists(path) then return { version = 1, keys = {} } end
    local handle = fs.open(path, "r")
    if not handle then return { version = 1, keys = {} } end
    local ok, data = pcall(textutils.unserialize, handle.readAll())
    handle.close()
    if ok and type(data) == "table" and type(data.keys) == "table" then return data end
    return { version = 1, keys = {} }
end

function trust.load(path) return loadData(path).keys end

function trust.save(path, keys)
    local directory = fs.getDir(path)
    if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
    local temporary, backup = path .. ".new", path .. ".bak"
    local handle = fs.open(temporary, "w")
    if not handle then return nil, "Cannot write trust store" end
    handle.write(textutils.serialize({ version = 1, keys = keys, updatedAt = os.epoch("utc") }))
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

function trust.add(path, node, key)
    local keys = trust.load(path)
    keys[node] = key
    return trust.save(path, keys)
end

function trust.remove(path, node)
    local keys = trust.load(path)
    keys[node] = nil
    return trust.save(path, keys)
end

return trust
