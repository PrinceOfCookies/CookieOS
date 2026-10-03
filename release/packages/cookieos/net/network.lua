local Envelope = require("cookieos.net.envelope")
local Canonical = require("cookieos.crypto.canonical")
local Trust = require("cookieos.trust")

local Network = {}
Network.__index = Network

local function contains(list, wanted)
    for _, value in ipairs(list or {}) do if value == wanted then return true end end
    return false
end

function Network.new(config, log)
    return setmetatable({
        config = config,
        log = log,
        transports = {},
        handlers = {},
        services = {},
        routes = {},
        seen = {},
        pending = {},
        requestRates = {},
        running = false,
    }, Network)
end

function Network:open()
    local persisted = Trust.load(self.config.network.trustPath)
    for node, key in pairs(persisted) do self.config.network.trustedKeys[node] = key end
    self.transports = {}
    for _, definition in ipairs(self.config.transports) do
        local modem = peripheral.wrap(definition.side)
        if not modem or peripheral.getType(definition.side) ~= "modem" then
            error("No modem on " .. definition.side)
        end
        modem.open(self.config.network.channel)
        modem.open(self.config.network.replyChannel)
        table.insert(self.transports, { name = definition.name, side = definition.side, modem = modem })
    end
end

function Network:addTrustedKey(node, key)
    self.config.network.trustedKeys[node] = key
    return Trust.add(self.config.network.trustPath, node, key)
end

function Network:removeTrustedKey(node)
    self.config.network.trustedKeys[node] = nil
    self.routes[node] = nil
    return Trust.remove(self.config.network.trustPath, node)
end

function Network:on(kind, handler)
    self.handlers[kind] = self.handlers[kind] or {}
    table.insert(self.handlers[kind], handler)
end

function Network:provide(service, handler)
    self.services[service] = handler
end

function Network:localServices()
    local result = {}
    for name in pairs(self.services) do table.insert(result, name) end
    table.sort(result)
    return result
end

function Network:transmit(packet)
    for _, transport in ipairs(self.transports) do
        transport.modem.transmit(self.config.network.channel, self.config.network.replyChannel, packet)
    end
end

function Network:send(kind, fields)
    fields = fields or {}
    fields.ttl = fields.ttl or self.config.network.ttl
    local packet = Envelope.new(self.config.node, kind, fields)
    if self.config.identity.nodeKey then Envelope.sign(packet, self.config.identity.nodeKey) end
    self.seen[packet.id] = os.clock()
    self:transmit(packet)
    return packet.id
end

function Network:emit(service, payload)
    local packet = Envelope.new(self.config.node, "event", {
        service = service,
        payload = payload,
        ttl = self.config.network.ttl,
    })
    if self.config.identity.nodeKey then Envelope.sign(packet, self.config.identity.nodeKey) end
    self.seen[packet.id] = os.clock()
    self:dispatch(packet)
    self:transmit(packet)
    return packet.id
end

function Network:announce()
    self:send("discovery", { payload = {
        apiMin = 3,
        apiMax = 3,
        signed = self.config.identity.nodeKey ~= nil,
        mode = self.config.mode,
        location = self.config.location,
        services = self:localServices(),
    } })
end

function Network:resolve(service)
    local selected, bestScore
    for node, route in pairs(self.routes) do
        local compatible = (route.apiMin or 3) <= 3 and (route.apiMax or 3) >= 3
        if compatible and contains(route.services, service) then
            local score = route.seenAt - ((route.failures or 0) * self.config.network.routeSeconds)
            if not bestScore or score > bestScore or (score == bestScore and node < selected) then
                selected, bestScore = node, score
            end
        end
    end
    return selected
end

function Network:reply(request, payload, ok, errorMessage)
    self:send("response", {
        destination = request.source,
        service = request.service,
        replyTo = request.id,
        payload = { ok = ok ~= false, data = payload, error = errorMessage },
    })
end

function Network:invoke(service, payload, packet)
    local handler = self.services[service]
    if not handler then return nil, "Service unavailable: " .. tostring(service) end
    local ok, result, serviceError = pcall(handler, payload, packet)
    if not ok then return nil, result end
    return result, serviceError
end

function Network:request(service, payload, timeout)
    if self.services[service] then
        local result, serviceError = self:invoke(service, payload, {
            source = self.config.node, service = service, kind = "request", localRequest = true,
        })
        if serviceError then return { ok = false, error = serviceError } end
        return { ok = true, data = result }
    end

    local destination = self:resolve(service)
    local attempts = self.config.network.requestRetries + 1
    for _ = 1, attempts do
        local id = self:send("request", {
            destination = destination,
            service = service,
            payload = payload,
        })
        local timer = os.startTimer(timeout or self.config.network.requestTimeout)
        while true do
            local event, first, second, third, fourth = os.pullEvent()
            if event == "modem_message" then
                self:receive(first, second, fourth)
            elseif event == "cookieos_response" and first == id then
                os.cancelTimer(timer)
                local route = self.routes[third]
                if route then route.failures = 0; route.lastSuccess = os.clock() end
                return second
            end
            if event == "timer" and first == timer then break end
        end
        if destination and self.routes[destination] then
            self.routes[destination].failures = (self.routes[destination].failures or 0) + 1
            destination = self:resolve(service)
        end
    end
    return nil, "Request timed out after " .. attempts .. " attempt(s): " .. service
end

function Network:prune()
    local now = os.clock()
    for id, at in pairs(self.seen) do
        if now - at > self.config.network.seenSeconds then self.seen[id] = nil end
    end
    for node, route in pairs(self.routes) do
        if now - route.seenAt > self.config.network.routeSeconds then self.routes[node] = nil end
    end
    for source, rate in pairs(self.requestRates) do
        if now - rate.startedAt > self.config.network.requestRateWindow then self.requestRates[source] = nil end
    end
end

local function countEntries(values)
    local count = 0
    for _ in pairs(values) do count = count + 1 end
    return count
end

local function removeOldest(values, field)
    local oldestKey, oldestValue
    for key, value in pairs(values) do
        local candidate = type(value) == "table" and value[field] or value
        if not oldestValue or candidate < oldestValue then oldestKey, oldestValue = key, candidate end
    end
    if oldestKey then values[oldestKey] = nil end
end

function Network:allowRequest(source)
    local now = os.clock()
    local rate = self.requestRates[source]
    if not rate or now - rate.startedAt > self.config.network.requestRateWindow then
        rate = { startedAt = now, count = 0 }
        self.requestRates[source] = rate
    end
    rate.count = rate.count + 1
    return rate.count <= self.config.network.requestRate
end

function Network:dispatch(packet)
    if packet.kind == "discovery" then
        if not self.routes[packet.source] and countEntries(self.routes) >= self.config.network.maxRoutes then
            removeOldest(self.routes, "seenAt")
        end
        self.routes[packet.source] = {
            seenAt = os.clock(), mode = packet.payload.mode, location = packet.payload.location,
            services = packet.payload.services or {}, apiMin = packet.payload.apiMin, apiMax = packet.payload.apiMax,
            signed = packet.payload.signed == true,
            failures = self.routes[packet.source] and self.routes[packet.source].failures or 0,
        }
    elseif packet.kind == "response" and packet.destination == self.config.node and packet.replyTo then
        os.queueEvent("cookieos_response", packet.replyTo, packet.payload, packet.source)
    elseif packet.kind == "request" and (not packet.destination or packet.destination == self.config.node) then
        if not self:allowRequest(packet.source) then
            self:reply(packet, nil, false, "Request rate limit exceeded")
        elseif self.services[packet.service] then
            local result, handlerError = self:invoke(packet.service, packet.payload, packet)
            self:reply(packet, result, handlerError == nil, handlerError)
        end
    end

    if not packet.destination or packet.destination == self.config.node then
        for _, handler in ipairs(self.handlers[packet.kind] or {}) do
            local ok, err = pcall(handler, packet)
            if not ok then self.log.error("Network handler failed: " .. tostring(err)) end
        end
    end
end

function Network:shouldRelay(packet)
    if self.config.mode ~= "relay" and self.config.mode ~= "hybrid" then return false end
    if packet.destination == self.config.node then return false end
    if packet.kind == "request" and self.services[packet.service] then return false end
    return packet.ttl > 1
end

function Network:receive(side, channel, packet)
    if channel ~= self.config.network.channel or not Envelope.valid(packet) then return end
    if packet.source == self.config.node or self.seen[packet.id] then return end
    local encodedOk, encoded = pcall(Canonical.encode, packet)
    if not encodedOk or #encoded > self.config.network.maxPacketBytes then return end
    if packet.ttl < 1 or packet.ttl > self.config.network.ttl then return end
    if math.abs(os.epoch("utc") - packet.sentAt) > self.config.network.maxClockSkewMs then return end

    local trustedKey = self.config.network.trustedKeys[packet.source]
    if trustedKey then
        if not Envelope.verify(packet, trustedKey) then
            self.log.warn("Rejected invalid signature from " .. packet.source)
            return
        end
    elseif self.config.network.requireSigned then
        self.log.warn("Rejected untrusted node " .. packet.source)
        return
    end
    self.seen[packet.id] = os.clock()
    if countEntries(self.seen) > self.config.network.maxSeenPackets then removeOldest(self.seen) end
    self:dispatch(packet)
    if self:shouldRelay(packet) then
        local forwarded = Envelope.copy(packet)
        forwarded.ttl = forwarded.ttl - 1
        self:transmit(forwarded)
    end
end

function Network:run()
    self:open()
    self.running = true
    self.lastActivity = os.clock()
    self:announce()
    local discoveryTimer = os.startTimer(self.config.network.discoverySeconds)
    local pruneTimer = os.startTimer(5)

    while self.running do
        local event, side, channel, _, packet = os.pullEvent()
        self.lastActivity = os.clock()
        if event == "modem_message" then
            self:receive(side, channel, packet)
        elseif event == "timer" and side == discoveryTimer then
            self:announce()
            discoveryTimer = os.startTimer(self.config.network.discoverySeconds)
        elseif event == "timer" and side == pruneTimer then
            self:prune()
            pruneTimer = os.startTimer(5)
        elseif event == "terminate" then
            self.running = false
        end
    end
end

return Network
