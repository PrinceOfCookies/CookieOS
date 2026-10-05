package.path = package.path .. ";/?.lua;/?/init.lua"
local Config = require("cookieos.config")
local Trust = require("cookieos.trust")
local config = Config.load(({ ... })[1] or "/cookieos-node.lua")
if not config.commandAuthority.authority then error("This computer is not the Command Authority") end
write("Node to revoke: "); local node = read()
if node == "" or node == config.node then error("Invalid revocation target") end
write("Revoke " .. node .. "? [y/N] ")
if read():lower() ~= "y" then print("Cancelled"); return end
assert(Trust.remove(config.network.trustPath, node))
local audit = fs.open("/cookieos-data/command-enrollment.log", "a")
if audit then audit.writeLine(textutils.serialize({ at = os.epoch("utc"), revoked = node })); audit.close() end
print("Revoked " .. node .. ".")
