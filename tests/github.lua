package.path = package.path .. ";/?.lua;/?/init.lua"

local closed = false
local requestedUrl, requestedHeaders
textutils = {
    unserializeJSON = function()
        return { encoding = "base64", content = "SGVs\nbG8=\n" }
    end,
}
http = {
    get = function(url, headers)
        requestedUrl, requestedHeaders = url, headers
        return {
            getResponseCode = function() return 200 end,
            readAll = function() return "json" end,
            close = function() closed = true end,
        }
    end,
}

local GitHub = require("cookieos.github")
local contents, err = GitHub.fetchFile("release/packages/a file.lua", "feature/test")
assert(contents == "Hello", err)
assert(closed)
assert(requestedUrl:find("a%%20file.lua", 1, false))
assert(requestedUrl:find("ref=feature%%2Ftest", 1, false))
assert(requestedHeaders["User-Agent"] == "CookieOS")

closed = false
http.get = function()
    return nil, "Not Found", {
        getResponseCode = function() return 404 end,
        readAll = function() return "error" end,
        close = function() closed = true end,
    }
end
textutils.unserializeJSON = function() return { message = "Not Found" } end
local missing, missingError = GitHub.fetchFile("missing.lua")
assert(missing == nil and missingError:find("404", 1, true))
assert(closed)
print("GitHub API helper tests passed.")
