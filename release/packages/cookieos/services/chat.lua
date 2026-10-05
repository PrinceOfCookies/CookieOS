local service = {}

service.manifest = {
    name = "chat", version = "3.6.0", provides = { "chat.send", "chat.status", "chat.history" },
    depends = { "node" }, peripherals = { "chatBox" },
}

function service.register(context)
    local chatBox = peripheral.find("chatBox")
    if not chatBox then error("chat service requires a chatBox") end
    local options = context.config.chat or {}
    local displayName = options.displayName or "CookieSecurity"
    local history = {}

    local function send(message)
        local ok, result = pcall(chatBox.sendMessage, tostring(message), displayName, options.prefix or "[]")
        if not ok then return nil, tostring(result) end
        return true
    end

    context.network:provide("chat.status", function() return { displayName = displayName, commands = options.commands == true } end)
    context.network:provide("chat.send", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "chat.send")
        if not allowed then return nil, reason end
        local message = tostring(payload.message or "")
        if message == "" then return nil, "Message is required" end
        local channel = tostring(payload.channel or "global"):lower()
        if not channel:match("^[%w_%-]+$") then return nil, "Invalid channel" end
        local recipient = payload.recipient and tostring(payload.recipient) or nil
        local rendered = "[" .. channel .. "] " .. (recipient and ("to " .. recipient .. ": ") or "") .. message
        local ok, err = send(rendered)
        if not ok then return nil, err end
        history[#history + 1] = { at = os.epoch("utc"), channel = channel, recipient = recipient, message = message, source = packet.source }
        while #history > (options.historyLimit or 100) do table.remove(history, 1) end
        context.publish("chat.message", history[#history])
        return { sent = true, channel = channel, recipient = recipient }
    end)
    context.network:provide("chat.history", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "chat.send")
        if not allowed then return nil, reason end
        local result = {}; local channel = payload.channel and tostring(payload.channel):lower()
        for _, entry in ipairs(history) do if not channel or entry.channel == channel then result[#result + 1] = entry end end
        return { messages = result, total = #result }
    end)

    if options.commands then
        context.supervisor:add("chat-commands", function()
            while true do
                local _, username, message = os.pullEvent("chat")
                message = tostring(message or "")
                if message == "!help" then
                    send("Commands: !help, !where <player>, !security")
                elseif message:match("^!where%s+") then
                    local query = message:match("^!where%s+(.+)$")
                    local actor = (options.users or {})[username]
                    local response = context.network:request("players.lookup", { query = query, actor = actor })
                    send(response and response.ok and textutils.serialize(response.data, { compact = true }) or "Lookup denied or unavailable")
                elseif message == "!security" then
                    local actor = (options.users or {})[username]
                    local response = context.network:request("security.get", { actor = actor })
                    send(response and response.ok and ("Security: " .. tostring(response.data.level)) or "Security status denied or unavailable")
                end
            end
        end, { restart = true })
    end
end

return service
