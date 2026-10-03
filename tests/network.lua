package.path = package.path .. ";/?.lua;/?/init.lua"

local Envelope = require("cookieos.net.envelope")
local Network = require("cookieos.net.network")

local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error("FAILED " .. name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("PASS " .. name)
end

local function network(mode)
    return Network.new({
        node = "test-node",
        mode = mode or "client",
        location = "test",
        identity = {},
        transports = {},
        network = {
            channel = 42420, replyChannel = 42421, ttl = 8,
            routeSeconds = 45, seenSeconds = 60,
            requestRetries = 0, requestTimeout = 0.1,
            requireSigned = false, trustedKeys = {}, maxClockSkewMs = 120000,
            maxPacketBytes = 16384, maxSeenPackets = 2048, maxRoutes = 256,
            requestRate = 30, requestRateWindow = 10,
        },
    }, { error = function(message) error(message) end, warn = function() end })
end

test("envelope validation", function()
    local packet = Envelope.new("alpha", "event", { ttl = 4, service = "test" })
    assert(Envelope.valid(packet))
    packet.ttl = nil
    assert(not Envelope.valid(packet))
end)

test("compatible service route", function()
    local net = network()
    net.routes.old = { seenAt = 100, apiMin = 2, apiMax = 2, services = { "auth.check" } }
    net.routes.good = { seenAt = 50, apiMin = 3, apiMax = 3, services = { "auth.check" } }
    assert(net:resolve("auth.check") == "good")
end)

test("failed route loses priority", function()
    local net = network()
    net.routes.alpha = { seenAt = 100, failures = 1, services = { "node.ping" } }
    net.routes.beta = { seenAt = 90, failures = 0, services = { "node.ping" } }
    assert(net:resolve("node.ping") == "beta")
end)

test("relay decrements ttl and deduplicates", function()
    local net = network("relay")
    local sent = {}
    net.transports = {{ modem = { transmit = function(_, _, packet) table.insert(sent, packet) end } }}
    local packet = Envelope.new("remote", "event", { ttl = 3, service = "example" })
    net:receive("back", 42420, packet)
    net:receive("back", 42420, packet)
    assert(#sent == 1)
    assert(sent[1].ttl == 2)
end)

test("signed packet accepts trusted source", function()
    local net = network("relay")
    net.config.network.requireSigned = true
    net.config.network.trustedKeys.remote = "secret"
    local sent = {}
    net.transports = {{ modem = { transmit = function(_, _, packet) table.insert(sent, packet) end } }}
    local packet = Envelope.new("remote", "event", { ttl = 3, service = "example" })
    Envelope.sign(packet, "secret")
    net:receive("back", 42420, packet)
    assert(#sent == 1)
end)

test("tampered signed packet is rejected", function()
    local net = network("relay")
    net.config.network.requireSigned = true
    net.config.network.trustedKeys.remote = "secret"
    local sent = {}
    net.transports = {{ modem = { transmit = function(_, _, packet) table.insert(sent, packet) end } }}
    local packet = Envelope.new("remote", "event", { ttl = 3, service = "example", payload = { value = 1 } })
    Envelope.sign(packet, "secret")
    packet.payload.value = 2
    net:receive("back", 42420, packet)
    assert(#sent == 0)
end)

test("oversized packet is rejected", function()
    local net = network("relay")
    net.config.network.maxPacketBytes = 256
    local sent = {}
    net.transports = {{ modem = { transmit = function(_, _, packet) table.insert(sent, packet) end } }}
    local packet = Envelope.new("remote", "event", { ttl = 3, service = "example", payload = string.rep("x", 512) })
    net:receive("back", 42420, packet)
    assert(#sent == 0)
end)

test("request rate is bounded", function()
    local net = network()
    net.config.network.requestRate = 1
    local calls = 0
    net:provide("example", function() calls = calls + 1; return true end)
    net.transports = {{ modem = { transmit = function() end } }}
    net:receive("back", 42420, Envelope.new("remote", "request", {
        ttl = 3, destination = "test-node", service = "example",
    }))
    net:receive("back", 42420, Envelope.new("remote", "request", {
        ttl = 3, destination = "test-node", service = "example",
    }))
    assert(calls == 1)
end)


print("All " .. passed .. " network tests passed")
