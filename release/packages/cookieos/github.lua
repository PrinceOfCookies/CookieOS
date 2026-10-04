local github = {}

local API_ROOT = "https://api.github.com/repos/"
local DEFAULT_REPOSITORY = "PrinceOfCookies/CookieOS"
local DEFAULT_REF = "cookieos-v3-rewrite"
local HEADERS = {
    ["User-Agent"] = "CookieOS",
    ["Accept"] = "application/vnd.github+json",
    ["X-GitHub-Api-Version"] = "2022-11-28",
}

local function encode(value)
    return (tostring(value):gsub("([^%w%-_%.~])", function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end

local function encodePath(path)
    local parts = {}
    for part in tostring(path):gmatch("[^/]+") do parts[#parts + 1] = encode(part) end
    return table.concat(parts, "/")
end

local function readResponse(response)
    local code
    if response.getResponseCode then
        local codeOk, value = pcall(response.getResponseCode)
        if codeOk then code = value end
    end
    local readOk, body = pcall(response.readAll)
    pcall(response.close)
    if not readOk then return nil, "Could not read GitHub API response: " .. tostring(body) end
    return body, nil, code
end

function github.fetchFile(path, ref, repository)
    if not http then return nil, "HTTP is disabled" end
    if type(textutils.decodeBase64) ~= "function" then
        return nil, "This CC:Tweaked version does not provide textutils.decodeBase64"
    end
    repository = repository or DEFAULT_REPOSITORY
    ref = ref or DEFAULT_REF
    local url = API_ROOT .. repository .. "/contents/" .. encodePath(path) .. "?ref=" .. encode(ref)
    local response, requestError, errorResponse = http.get(url, HEADERS)
    response = response or errorResponse
    if not response then return nil, "GitHub API request failed: " .. tostring(requestError) end
    local body, readError, code = readResponse(response)
    if not body then return nil, readError end
    local decodeOk, payload = pcall(textutils.unserializeJSON, body)
    if not decodeOk or type(payload) ~= "table" then
        return nil, "GitHub API returned invalid JSON" .. (code and " (HTTP " .. code .. ")" or "")
    end
    if code and code >= 400 then
        return nil, "GitHub API error " .. code .. ": " .. tostring(payload.message or "unknown error")
    end
    if payload.message and not payload.content then return nil, "GitHub API error: " .. tostring(payload.message) end
    if payload.encoding ~= "base64" or type(payload.content) ~= "string" then
        return nil, "GitHub API response did not contain base64 file content"
    end
    local cleanContent = payload.content:gsub("%s", "")
    local base64Ok, contents = pcall(textutils.decodeBase64, cleanContent)
    if not base64Ok or type(contents) ~= "string" then
        return nil, "GitHub API returned invalid base64 content: " .. tostring(contents)
    end
    return contents
end

github.defaultRepository = DEFAULT_REPOSITORY
github.defaultRef = DEFAULT_REF

return github
