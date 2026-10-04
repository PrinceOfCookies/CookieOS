package.path = package.path .. ";/?.lua;/?/init.lua"

local Config = require("cookieos.config")
local GitHub = require("cookieos.github")
local Update = require("cookieos.update")
local args = { ... }
local manifestLocation = args[1]
local config = Config.load(args[2] or "/cookieos-node.lua")

local function fetchHttpFile(url)
    local response, requestError, errorResponse = http.get(url, { ["User-Agent"] = "CookieOS" })
    response = response or errorResponse
    if not response then return nil, "HTTP request failed: " .. tostring(requestError) end
    local code
    if response.getResponseCode then
        local codeOk, value = pcall(response.getResponseCode)
        if codeOk then code = value end
    end
    local readOk, body = pcall(response.readAll)
    pcall(response.close)
    if not readOk then return nil, "Could not read HTTP response: " .. tostring(body) end
    if code and code >= 400 then return nil, "HTTP request failed with status " .. code end
    return body
end

local requestedRef
local raw, manifestError
if manifestLocation and manifestLocation:match("^https?://") then
    raw, manifestError = fetchHttpFile(manifestLocation)
else
    requestedRef = manifestLocation or GitHub.defaultRef
    raw, manifestError = GitHub.fetchFile("release/manifest.json", requestedRef)
end
if not raw then error("Manifest download failed: " .. tostring(manifestError)) end
local manifest = textutils.unserializeJSON(raw)
if type(manifest) ~= "table" then error("Manifest is not valid JSON") end
local repository = manifest.repository or GitHub.defaultRepository
local releaseRef = requestedRef or manifest.ref or GitHub.defaultRef

local ok, stageError = Update.stage(config, manifest, function(file)
    if type(file.source) == "string" then return GitHub.fetchFile(file.source, releaseRef, repository) end
    if type(file.url) == "string" then return fetchHttpFile(file.url) end
    return nil, "Manifest entry has no source"
end)
if not ok then error(stageError) end
print("Staged CookieOS " .. manifest.version .. " with " .. #manifest.files .. " file(s).")
write("Apply and reboot now? [y/N] ")
if read():lower() == "y" then
    local applied, applyError = Update.apply(config)
    if not applied then error(applyError) end
    os.reboot()
end
