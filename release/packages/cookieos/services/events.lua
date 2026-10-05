local service = {}
local Canonical = require("cookieos.crypto.canonical")

service.manifest = {
    name = "events", version = "3.3.0",
    provides = { "events.publish", "events.subscribe", "events.unsubscribe", "events.topics", "events.recent", "notify.send" },
    depends = { "node" },
}

function service.register(context)
    local options = context.config.events or {}
    local topics, subscriptions, localHandlers = {}, {}, {}
    local sequence = 0

    local function validTopic(topic)
        return type(topic) == "string" and #topic > 0 and #topic <= 80
            and topic:match("^[%w%._%-]+$") ~= nil
    end

    local function topicCount()
        local count = 0
        for _ in pairs(topics) do count = count + 1 end
        return count
    end

    local function subscriptionCount()
        local count = 0
        for _, nodeTopics in pairs(subscriptions) do
            for _ in pairs(nodeTopics) do count = count + 1 end
        end
        return count
    end

    local function publish(topic, payload, publishOptions)
        publishOptions = publishOptions or {}
        if not validTopic(topic) then return nil, "Invalid event topic" end
        local encodedOk, encoded = pcall(Canonical.encode, payload)
        if not encodedOk or #encoded > (options.maxEventBytes or 8192) then return nil, "Event payload is too large or invalid" end
        if not topics[topic] then
            if topicCount() >= (options.maxTopics or 128) then return nil, "Event topic limit reached" end
            topics[topic] = {}
        end
        sequence = sequence + 1
        local event = {
            id = context.config.node .. ":event:" .. sequence,
            topic = topic, at = os.epoch("utc"), source = publishOptions.source or context.config.node,
            payload = payload,
        }
        if publishOptions.retain ~= false then
            table.insert(topics[topic], event)
            while #topics[topic] > (options.retainedPerTopic or 20) do table.remove(topics[topic], 1) end
        end
        for _, handler in ipairs(localHandlers[topic] or {}) do
            local ok, err = pcall(handler, event)
            if not ok then context.log.error("Event handler failed for " .. topic .. ": " .. tostring(err)) end
        end
        local now = os.epoch("utc")
        for node, nodeTopics in pairs(subscriptions) do
            local expiry = nodeTopics[topic]
            if expiry and expiry > now then
                context.network:send("event", { destination = node, service = topic, payload = event })
            elseif expiry then
                nodeTopics[topic] = nil
            end
        end
        return event
    end

    context.events = {
        publish = publish,
        on = function(topic, handler)
            localHandlers[topic] = localHandlers[topic] or {}
            table.insert(localHandlers[topic], handler)
        end,
    }

    context.network:provide("events.publish", function(payload, packet)
        local trusted = packet.localRequest or (options.publishers and options.publishers[packet.source] == true)
        if not trusted then return nil, "Node is not an event publisher" end
        local event, err = publish(payload.topic, payload.payload, {
            retain = payload.retain, source = packet.source,
        })
        if not event then return nil, err end
        return event
    end)

    context.network:provide("events.subscribe", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "events.subscribe")
        if not allowed then return nil, reason end
        if not validTopic(payload.topic) then return nil, "Invalid event topic" end
        subscriptions[packet.source] = subscriptions[packet.source] or {}
        if not subscriptions[packet.source][payload.topic]
            and subscriptionCount() >= (options.maxSubscriptions or 512) then
            return nil, "Event subscription limit reached"
        end
        subscriptions[packet.source][payload.topic] = os.epoch("utc") + ((options.subscriptionSeconds or 300) * 1000)
        return { topic = payload.topic, expiresAt = subscriptions[packet.source][payload.topic], retained = topics[payload.topic] or {} }
    end)

    context.network:provide("events.unsubscribe", function(payload, packet)
        if subscriptions[packet.source] then subscriptions[packet.source][payload.topic] = nil end
        return { removed = true, topic = payload.topic }
    end)

    context.network:provide("events.topics", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "events.view")
        if not allowed then return nil, reason end
        local result = {}
        for topic, retained in pairs(topics) do table.insert(result, { topic = topic, retained = #retained }) end
        table.sort(result, function(a, b) return a.topic < b.topic end)
        return { topics = result }
    end)

    context.network:provide("events.recent", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "events.view")
        if not allowed then return nil, reason end
        if not validTopic(payload.topic) then return nil, "Invalid event topic" end
        return { topic = payload.topic, events = topics[payload.topic] or {} }
    end)

    context.network:provide("notify.send", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "notifications.send")
        if not allowed then return nil, reason end
        local message = tostring(payload.message or "")
        if message == "" then return nil, "Notification message is required" end
        if #message > 240 then return nil, "Notification must be 1-240 characters" end
        local severity = tostring(payload.severity or "info"):lower()
        if not severity:match("^(info|notice|warning|critical|emergency)$") then
            return nil, "Severity must be info, notice, warning, critical, or emergency"
        end
        local event, eventError = publish("notification." .. severity, {
            message = message, severity = severity, channels = payload.channels or { "monitor" }, source = packet.source,
        }, { source = packet.source, retain = false })
        if not event then return nil, eventError end
        return { sent = true, event = event.id, severity = severity, message = message }
    end)

    publish("node.started", { node = context.config.node, mode = context.config.mode })
end

function service.health(context)
    return context.events ~= nil, context.events and "publishing" or "not initialized"
end

return service
