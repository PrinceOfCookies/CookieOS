local envelope = {}
local Canonical = require("cookieos.crypto.canonical")
local Sha256 = require("cookieos.crypto.sha256")
local sequence = 0

local function nextId(node)
    sequence = sequence + 1
    return table.concat({ node, os.epoch("utc"), os.getComputerID(), sequence }, ":")
end

function envelope.new(node, kind, fields)
    fields = fields or {}
    return {
        cookieos = 3,
        id = fields.id or nextId(node),
        kind = kind,
        source = node,
        destination = fields.destination,
        service = fields.service,
        replyTo = fields.replyTo,
        ttl = fields.ttl,
        sentAt = os.epoch("utc"),
        payload = fields.payload,
    }
end

function envelope.valid(packet)
    return type(packet) == "table"
        and packet.cookieos == 3
        and type(packet.id) == "string"
        and type(packet.kind) == "string"
        and type(packet.source) == "string"
        and type(packet.ttl) == "number"
        and type(packet.sentAt) == "number"
end

function envelope.copy(packet)
    local result = {}
    for key, value in pairs(packet) do result[key] = value end
    return result
end

local function signable(packet)
    local result = {}
    for key, value in pairs(packet) do
        -- TTL changes at each relay. Receivers still enforce their configured
        -- maximum, while all routing and application fields remain signed.
        if key ~= "signature" and key ~= "ttl" then result[key] = value end
    end
    return Canonical.encode(result)
end

function envelope.sign(packet, key)
    packet.signature = Sha256.hmac(key, signable(packet))
    return packet.signature
end

function envelope.verify(packet, key)
    if type(packet.signature) ~= "string" or packet.signature == "" then return false end
    local expected = Sha256.hmac(key, signable(packet))
    local difference = #expected == #packet.signature and 0 or 1
    local length = math.max(#expected, #packet.signature)
    for index = 1, length do
        difference = bit32.bor(difference, bit32.bxor(expected:byte(index) or 0, packet.signature:byte(index) or 0))
    end
    return difference == 0
end

return envelope
