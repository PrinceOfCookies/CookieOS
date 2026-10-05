package.path = package.path .. ";/?.lua;/?/init.lua"
local Config = require("cookieos.config")
local Box = require("cookieos.crypto.box")
local Trust = require("cookieos.trust")
local Sha256 = require("cookieos.crypto.sha256")

local config = Config.load(({ ... })[1] or "/cookieos-node.lua")
if not config.commandAuthority.authority then error("This computer is not the Command Authority") end
local side = config.transports[1].side
if not rednet.isOpen(side) then rednet.open(side) end
local alphabet, result = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", {}
for index = 1, 16 do local at = math.random(1, #alphabet); result[index] = alphabet:sub(at, at) end
local code = table.concat(result)
print("Command Authority enrollment code:")
print(code)
print("Enter this on the new node within two minutes.")
local deadline = os.epoch("utc") + 120000
while os.epoch("utc") < deadline do
    local sender, packet = rednet.receive(config.pairing.protocol, 2)
    if type(packet) == "table" and packet.type == "pair_request" and packet.code == code then
        local plaintext = Box.open(code, packet.sealed)
        local ok, request = pcall(textutils.unserialize, plaintext or "")
        if ok and type(request) == "table" and type(request.node) == "string" and type(request.key) == "string" and #request.key >= 16 then
            local keys = Trust.load(config.network.trustPath)
            keys[request.node] = request.key
            assert(Trust.save(config.network.trustPath, keys))
            keys[config.node] = config.identity.nodeKey
            rednet.send(sender, { type = "pair_response", requestId = packet.requestId,
                sealed = Box.seal(code, textutils.serialize({ node = config.node, keys = keys })) }, config.pairing.protocol)
            local audit = fs.open("/cookieos-data/command-enrollment.log", "a")
            if audit then audit.writeLine(textutils.serialize({ at = os.epoch("utc"), node = request.node,
                fingerprint = Sha256.hex(request.key):sub(1, 16) })); audit.close() end
            print("Enrolled " .. request.node .. " under Command Authority.")
            return
        end
    end
end
error("Enrollment code expired")
