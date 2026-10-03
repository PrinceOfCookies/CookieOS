package.path = package.path .. ";/?.lua;/?/init.lua"

local runtime = require("cookieos.runtime")
local configPath = ({ ... })[1] or "/cookieos-node.lua"
local Config = require("cookieos.config")
local Update = require("cookieos.update")
local config = Config.load(configPath)
local bootAllowed, state = Update.beginBoot(config)
if not bootAllowed then
    printError("Updated system failed to become healthy after " .. tostring(state.attempts) .. " boots.")
    print("Starting offline recovery.")
    shell.run("recovery.lua", configPath)
    return
end
runtime.start(configPath)
