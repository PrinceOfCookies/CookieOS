package.path = package.path .. ";/?.lua;/?/init.lua"

local Config = require("cookieos.config")
local Update = require("cookieos.update")
local args = { ... }
local manifestUrl = args[1]
if not manifestUrl then error("Usage: cookieos-update <manifest URL> [config path]") end
local config = Config.load(args[2] or "/cookieos-node.lua")

local response, requestError = http.get(manifestUrl)
if not response then error("Manifest download failed: " .. tostring(requestError)) end
local raw = response.readAll()
response.close()
local manifest = textutils.unserializeJSON(raw)
if type(manifest) ~= "table" then error("Manifest is not valid JSON") end

local ok, stageError = Update.stage(config, manifest, function(file)
    local fileResponse, fileError = http.get(file.url)
    if not fileResponse then return nil, fileError end
    local contents = fileResponse.readAll()
    fileResponse.close()
    return contents
end)
if not ok then error(stageError) end
print("Staged CookieOS " .. manifest.version .. " with " .. #manifest.files .. " file(s).")
write("Apply and reboot now? [y/N] ")
if read():lower() == "y" then
    local applied, applyError = Update.apply(config)
    if not applied then error(applyError) end
    os.reboot()
end
