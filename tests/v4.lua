package.path = package.path .. ";/?.lua;/?/init.lua"
local Identity = require("cookieos.v4.identity")
local credential = Identity.credential("node", "secret", "salt")
assert(Identity.verify(credential, "secret"))
assert(not Identity.verify(credential, "wrong"))
local Kernel = require("cookieos.v4.kernel")
local started = {}
local instance = Kernel.start(Kernel.new({ version = 4 }, {}), {
    { name = "base", start = function() started[#started + 1] = "base" end },
    { name = "ui", depends = { "base" }, start = function() started[#started + 1] = "ui" end },
})
assert(instance.running and started[1] == "base" and started[2] == "ui")
print("CookieOS v4 foundation tests passed")
