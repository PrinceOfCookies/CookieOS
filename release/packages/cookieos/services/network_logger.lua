local service = {}

service.manifest = {
    name = "network-logger", version = "1.0.0", provides = { "network.log" }, depends = { "node" },
}

function service.register(context)
    local options = context.config.networkLogger or {}
    local ignored = {}
    for _, node in ipairs(options.ignoreNodes or {}) do ignored[node] = true end
    local command = context.config.commandAuthority or {}
    if command.node then ignored[command.node] = true end
    for _, node in ipairs(command.peers or {}) do ignored[node] = true end
    local path = options.dataPath or "/cookieos-data/network.log"

    local function record(packet)
        if packet.kind ~= "request" or ignored[packet.source] then return end
        local directory = fs.getDir(path)
        if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
        local handle = fs.open(path, "a")
        if handle then
            handle.writeLine(textutils.serialize({ at = os.epoch("utc"), source = packet.source,
                destination = packet.destination, service = packet.service, requestId = packet.id }))
            handle.close()
        end
    end

    context.network:observe("request", record)
    context.network:provide("network.log", function()
        return { path = path, ignored = options.ignoreNodes or {} }
    end)
end

return service
