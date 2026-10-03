package.path = package.path .. ";/?.lua;/?/init.lua"

local Config = require("cookieos.config")
local Box = require("cookieos.crypto.box")
local Trust = require("cookieos.trust")

local args = { ... }
local config = Config.load(args[1] or "/cookieos-node.lua")
if not config.identity.nodeKey then error("Configure identity.nodeKey before pairing") end
local side = args[2] or config.transports[1].side
if not rednet.isOpen(side) then rednet.open(side) end

write("One-time pairing code: ")
local code = read():upper():gsub("%s", "")
if #code < 12 then error("Pairing code is too short") end
local requestId = config.node .. ":" .. os.epoch("utc") .. ":" .. math.random()
local sealed = Box.seal(code, textutils.serialize({ node = config.node, key = config.identity.nodeKey }))
rednet.broadcast({ type = "pair_request", requestId = requestId, code = code, sealed = sealed }, config.pairing.protocol)

local started = os.clock()
while os.clock() - started < 10 do
    local _, response = rednet.receive(config.pairing.protocol, 2)
    if type(response) == "table" and response.type == "pair_response" and response.requestId == requestId then
        local plaintext, openError = Box.open(code, response.sealed)
        if not plaintext then error(openError) end
        local authority = textutils.unserialize(plaintext)
        if type(authority) ~= "table" or type(authority.node) ~= "string" or type(authority.keys) ~= "table" then
            error("Invalid pairing response")
        end
        local keys = Trust.load(config.network.trustPath)
        for node, key in pairs(authority.keys) do
            if type(node) == "string" and type(key) == "string" then keys[node] = key end
        end
        local ok, saveError = Trust.save(config.network.trustPath, keys)
        if not ok then error(saveError) end
        print("Paired with " .. authority.node .. ". Restart CookieOS to join the signed network.")
        return
    end
end
error("Pairing timed out")
