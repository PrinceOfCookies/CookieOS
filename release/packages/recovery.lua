package.path = package.path .. ";/?.lua;/?/init.lua"

local Config = require("cookieos.config")
local Update = require("cookieos.update")
local args = { ... }
local configPath = args[1] or "/cookieos-node.lua"
local ok, config = pcall(Config.load, configPath)
if not ok then
    config = { update = {
        statePath = "/cookieos-update/state.db", stagePath = "/cookieos-update/staged",
        backupPath = "/cookieos-update/backup",
    } }
end

local function disabledServices()
    local path = "/cookieos-data/disabled-services.db"
    if not fs.exists(path) then return {} end
    local handle = fs.open(path, "r")
    local value = handle and textutils.unserialize(handle.readAll()) or {}
    if handle then handle.close() end
    return type(value) == "table" and value or {}
end

local function saveDisabled(value)
    if not fs.exists("/cookieos-data") then fs.makeDir("/cookieos-data") end
    local handle = assert(fs.open("/cookieos-data/disabled-services.db", "w"))
    handle.write(textutils.serialize(value))
    handle.close()
end

while true do
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("CookieOS Offline Recovery")
    print("1. Roll back last update")
    print("2. Disable a service")
    print("3. Enable all services")
    print("4. Restore a .bak file")
    print("5. View runtime log")
    print("6. Reboot")
    print("7. Exit to shell")
    write("> ")
    local choice = read()
    if choice == "1" then
        local rolledBack, rollbackError = Update.rollback(config)
        print(rolledBack and "Update rolled back." or ("Rollback failed: " .. tostring(rollbackError)))
    elseif choice == "2" then
        write("Service manifest name: ")
        local name = read()
        local disabled = disabledServices()
        disabled[name] = true
        saveDisabled(disabled)
        print("Disabled " .. name)
    elseif choice == "3" then
        saveDisabled({})
        print("All configured services enabled.")
    elseif choice == "4" then
        write("Target path (backup must be target.bak): ")
        local target = read()
        local backup = target .. ".bak"
        if target:sub(1, 1) ~= "/" or target:find("..", 1, true) or not fs.exists(backup) then
            printError("Invalid target or backup not found.")
        else
            write("Replace " .. target .. " from backup? [y/N] ")
            if read():lower() == "y" then
                if fs.exists(target) then fs.delete(target) end
                fs.copy(backup, target)
                print("Backup restored.")
            end
        end
    elseif choice == "5" then
        if fs.exists("/cookieos-data/runtime.log") then shell.run("edit", "/cookieos-data/runtime.log")
        else print("No runtime log found.") end
    elseif choice == "6" then
        os.reboot()
    elseif choice == "7" then
        return
    end
    print("Press any key to continue")
    os.pullEvent("key")
end
