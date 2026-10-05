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

local function decodeBase64(value)
    value = value:gsub("%s", "")
    if type(textutils.decodeBase64) == "function" then return textutils.decodeBase64(value) end
    if #value % 4 ~= 0 then error("invalid base64 length") end
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for index = 1, #alphabet do lookup[alphabet:sub(index, index)] = index - 1 end
    local output = {}
    for offset = 1, #value, 4 do
        local a, b, c, d = value:sub(offset, offset), value:sub(offset + 1, offset + 1), value:sub(offset + 2, offset + 2), value:sub(offset + 3, offset + 3)
        if not lookup[a] or not lookup[b] or (c ~= "=" and not lookup[c]) or (d ~= "=" and not lookup[d]) or (c == "=" and d ~= "=") then
            error("invalid base64 data")
        end
        if (c == "=" or d == "=") and offset + 3 ~= #value then error("invalid base64 padding") end
        local combined = lookup[a] * 262144 + lookup[b] * 4096 + (lookup[c] or 0) * 64 + (lookup[d] or 0)
        output[#output + 1] = string.char(math.floor(combined / 65536) % 256)
        if c ~= "=" then output[#output + 1] = string.char(math.floor(combined / 256) % 256) end
        if d ~= "=" then output[#output + 1] = string.char(combined % 256) end
        if offset % 32768 == 1 and os.queueEvent and os.pullEvent then
            os.queueEvent("cookieos_github_yield")
            os.pullEvent("cookieos_github_yield")
        end
    end
    return table.concat(output)
end

function github.fetchFile(path, ref, repository)
    if not http then return nil, "HTTP is disabled" end
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
    local base64Ok, contents = pcall(decodeBase64, payload.content)
    if not base64Ok or type(contents) ~= "string" then
        return nil, "GitHub API returned invalid base64 content: " .. tostring(contents)
    end
    return contents
end

github.defaultRepository = DEFAULT_REPOSITORY
github.defaultRef = DEFAULT_REF

return github
