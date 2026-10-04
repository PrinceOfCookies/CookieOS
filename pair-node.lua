package.path = package.path .. ";/?.lua;/?/init.lua"

local Config = require("cookieos.config")
local Box = require("cookieos.crypto.box")
local Trust = require("cookieos.trust")

local args = { ... }
local config = Config.load(args[1] or "/cookieos-node.lua")
if not config.identity.nodeKey then error("Configure identity.nodeKey before pairing") end
local side = args[2] or config.transports[1].side
if not rednet.isOpen(side) then rednet.open(side) end

print("The CookieOS authority server must generate the pairing code.")
print("On an authenticated administrator terminal, run: paircode")
print("Then enter the 16-character one-time code shown there.")
local code
while not code do
    write("Authority pairing code: ")
    local entered = read():upper():gsub("[%s%-]", "")
    if #entered == 16 and not entered:find("[^ABCDEFGHJKLMNPQRSTUVWXYZ23456789]") then
        code = entered
    else
        printError("Invalid code. Enter exactly 16 characters from the authority's paircode command.")
    end
end
local requestId = config.node .. ":" .. os.epoch("utc") .. ":" .. math.random()
local sealed = Box.seal(code, textutils.serialize({ node = config.node, key = config.identity.nodeKey }))
local protocol = config.pairing and config.pairing.protocol or "cookieos_pairing"
rednet.broadcast({ type = "pair_request", requestId = requestId, code = code, sealed = sealed }, protocol)

local started = os.clock()
while os.clock() - started < 10 do
    local _, response = rednet.receive(protocol, 2)
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
