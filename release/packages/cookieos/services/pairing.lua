local service = {}
local Box = require("cookieos.crypto.box")

service.manifest = {
    name = "pairing", version = "3.4.0",
    provides = { "pairing.begin", "pairing.revoke", "pairing.status" },
    depends = { "auth", "node" },
}

local alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

local function newCode()
    local result = {}
    for index = 1, 16 do
        local at = math.random(1, #alphabet)
        result[index] = alphabet:sub(at, at)
    end
    return table.concat(result)
end

function service.register(context)
    local options = context.config.pairing or {}
    if not options.authority then error("pairing service requires pairing.authority = true") end
    if not context.config.identity.nodeKey then error("pairing authority requires identity.nodeKey") end
    local pending = {}
    local protocol = options.protocol or "cookieos_pairing"
    local side = options.side or context.config.transports[1].side
    if not rednet.isOpen(side) then rednet.open(side) end

    local function prune()
        local now = os.epoch("utc")
        local count = 0
        for code, record in pairs(pending) do
            if record.expiresAt <= now then pending[code] = nil else count = count + 1 end
        end
        return count
    end

    context.network:provide("pairing.begin", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "pairing.manage")
        if not allowed then return nil, reason end
        if prune() >= (options.maxPending or 8) then return nil, "Too many pending pairing codes" end
        local code = newCode()
        pending[code] = {
            expiresAt = os.epoch("utc") + ((options.codeSeconds or 120) * 1000),
            actor = payload.actor or "session",
        }
        if context.audit then context.audit.write("pairing.code.created", { actor = payload.actor or "session" }) end
        return { code = code, expiresAt = pending[code].expiresAt, protocol = protocol }
    end)

    context.network:provide("pairing.revoke", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "pairing.manage")
        if not allowed then return nil, reason end
        local node = tostring(payload.node or "")
        if node == "" then return nil, "Node is required" end
        local ok, err = context.network:removeTrustedKey(node)
        if not ok then return nil, err end
        if context.audit then context.audit.write("pairing.node.revoked", { actor = payload.actor or "session", details = { node = node } }) end
        context.publish("node.revoked", { node = node })
        return { revoked = node }
    end)

    context.network:provide("pairing.status", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "pairing.manage")
        if not allowed then return nil, reason end
        local trusted = {}
        for node in pairs(context.config.network.trustedKeys) do table.insert(trusted, node) end
        table.sort(trusted)
        return { pending = prune(), trusted = trusted }
    end)

    context.supervisor:add("pairing.bootstrap", function()
        while true do
            local sender, packet = rednet.receive(protocol, 1)
            if sender and type(packet) == "table" and packet.type == "pair_request" and pending[packet.code] then
                local record = pending[packet.code]
                if record.expiresAt > os.epoch("utc") then
                    local plaintext = Box.open(packet.code, packet.sealed)
                    local ok, request = pcall(textutils.unserialize, plaintext or "")
                    if ok and type(request) == "table" and type(request.node) == "string"
                        and request.node ~= "" and type(request.key) == "string" and #request.key >= 16 then
                        pending[packet.code] = nil
                        local stored, storeError = context.network:addTrustedKey(request.node, request.key)
                        if stored then
                            local keys = {}
                            for node, key in pairs(context.config.network.trustedKeys) do keys[node] = key end
                            keys[context.config.node] = context.config.identity.nodeKey
                            local response = textutils.serialize({ node = context.config.node, keys = keys })
                            rednet.send(sender, {
                                type = "pair_response", requestId = packet.requestId,
                                sealed = Box.seal(packet.code, response),
                            }, protocol)
                            if context.audit then
                                context.audit.write("pairing.node.joined", {
                                    actor = record.actor, details = { node = request.node, computerId = sender },
                                })
                            end
                            context.publish("node.paired", { node = request.node })
                        else
                            context.log.error("Pairing trust write failed: " .. tostring(storeError))
                        end
                    end
                end
            end
        end
    end)
end

return service
