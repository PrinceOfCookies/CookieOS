local gateway = {}

function gateway.register(context)
    local options = context.config.legacy or {}
    if not options.enabled then return end

    local side = options.side or context.config.transports[1].side
    local coreProtocol = options.coreProtocol or "subterra_core"
    local authProtocol = options.authProtocol or "subterra_auth"

    if not rednet.isOpen(side) then rednet.open(side) end

    context.supervisor:add("legacy.subterra", function()
        while true do
            local sender, packet, protocol = rednet.receive(nil, 1)
            if sender and type(packet) == "table" and packet.app == "subterra" then
                if protocol == coreProtocol and packet.type == "heartbeat" then
                    context.network:emit("legacy.subterra.heartbeat", { sender = sender, packet = packet })
                elseif protocol == coreProtocol and packet.type == "request_security_state" and context.security then
                    rednet.send(sender, {
                        app = "subterra",
                        type = "security_state",
                        level = context.security.get(),
                        source = context.config.node,
                    }, coreProtocol)
                elseif protocol == coreProtocol and packet.type == "security_level" then
                    context.network:invoke("security.set", {
                        level = packet.level,
                        actor = packet.actor,
                        legacy = true,
                    }, { source = "legacy:" .. sender, legacy = true })
                elseif protocol == authProtocol and packet.type == "auth_check" then
                    local data = packet.data or packet
                    local result, err = context.network:invoke("auth.check", data, { source = "legacy:" .. sender, legacy = true })
                    result = result or { allowed = false, reason = err }
                    result.app = "subterra"
                    result.type = "auth_response"
                    result.requestId = data.requestId or packet.requestId
                    result.permission = data.permission or data.perm
                    rednet.send(sender, result, authProtocol)
                elseif protocol == authProtocol and packet.type == "auth_list_users" then
                    local data = packet.data or packet
                    local result, err = context.network:invoke("auth.users.list", data, { source = "legacy:" .. sender, legacy = true })
                    rednet.send(sender, {
                        app = "subterra", type = "auth_list_users_response",
                        requestId = data.requestId or packet.requestId,
                        ok = result ~= nil, reason = err,
                        users = result and result.users or {},
                    }, authProtocol)
                elseif protocol == authProtocol and packet.type == "auth_manage" then
                    local data = packet.data or packet
                    local names = {
                        add = "auth.user.set", set = "auth.user.set", remove = "auth.user.remove",
                        addperm = "auth.permission.add", removeperm = "auth.permission.remove",
                    }
                    local serviceName = names[data.action]
                    local result, err
                    if serviceName then
                        result, err = context.network:invoke(serviceName, data, { source = "legacy:" .. sender, legacy = true })
                    else
                        err = "Unknown auth action"
                    end
                    rednet.send(sender, {
                        app = "subterra", type = "auth_manage_response",
                        requestId = data.requestId or packet.requestId,
                        ok = result ~= nil, reason = err or "Updated",
                    }, authProtocol)
                end
            end
        end
    end)

    context.network:on("event", function(packet)
        if packet.service == "security.changed" then
            rednet.broadcast({
                app = "subterra",
                type = "security_state",
                level = packet.payload.level,
                source = context.config.node,
            }, coreProtocol)
        end
    end)
end

return gateway
