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
local started, startError = pcall(runtime.start, configPath)
if not started then
    os.startTimer(0)
    while true do
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.red)
        term.clear()
        term.setCursorPos(1, 1)
        print("CookieSecurity is locked.")
        print("Startup could not verify Command Authority enrollment.")
        printError(tostring(startError))
        print("No shell access is available on this terminal.")
        print("Complete enrollment from the Command Authority, then reboot.")
        os.pullEventRaw("timer")
        os.startTimer(10)
    end
end
