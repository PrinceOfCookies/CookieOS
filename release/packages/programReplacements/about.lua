local version = "not installed"
if fs.exists("/cookieos-install/installed.db") then
    local handle = fs.open("/cookieos-install/installed.db", "r")
    local state = handle and textutils.unserialize(handle.readAll())
    if handle then handle.close() end
    if type(state) == "table" then version = state.version or version end
end
print("CookieSecurity " .. tostring(version))
print(os.version() .. " on " .. tostring(_HOST))
print("Computer " .. os.getComputerID() .. " | " .. (os.getComputerLabel() or "unlabelled"))
