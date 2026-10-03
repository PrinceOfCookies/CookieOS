package.path = package.path .. ";/?.lua;/?/init.lua"
local Sha256 = require("cookieos.crypto.sha256")

local files = {}
fs = {
    getDir = function(path) return path:match("^(.*)/[^/]+$") or "" end,
    exists = function(path) return files[path] ~= nil or path == "/cookieos-data" end,
    makeDir = function() end,
    delete = function(path) files[path] = nil end,
    move = function(from, to) assert(files[from], "missing source"); files[to] = files[from]; files[from] = nil end,
    open = function(path, mode)
        if mode == "r" then
            if not files[path] then return nil end
            return { readAll = function() return files[path] end, close = function() end }
        end
        local chunks = {}
        return {
            write = function(value) table.insert(chunks, value) end,
            close = function() files[path] = table.concat(chunks) end,
        }
    end,
}

local function serialize(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    local parts = { "{" }
    for key, child in pairs(value) do
        table.insert(parts, "[" .. serialize(key) .. "]=" .. serialize(child) .. ",")
    end
    table.insert(parts, "}")
    return table.concat(parts)
end

textutils = {
    serialize = serialize,
    unserialize = function(value)
        local chunk = assert(load("return " .. value, "database", "t", {}))
        return chunk()
    end,
}

local handlers = {}
local context = {
    config = {
        node = "auth-server",
        identity = {},
        legacy = {},
        auth = {
            dataPath = "/cookieos-data/users.db",
            trustedNodes = { terminal = "admin" },
            delegates = { tracker = true },
            seedUsers = {
                admin = { clearance = 5, role = "Admin", status = "Active", extraPermissions = { "all" }, password = "test-password" },
                worker = { clearance = 1, role = "Worker", status = "Active" },
                fired = { clearance = 5, role = "Former", status = "FIRED" },
            },
        },
    },
    log = { info = function() end },
    publish = function() end,
    network = { provide = function(_, name, handler) handlers[name] = handler end },
}

require("cookieos.services.auth").register(context)

local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error("FAILED " .. name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("PASS " .. name)
end

test("clearance permits known user", function()
    local result = handlers["auth.check"]({ user = "worker", permission = "security.view" })
    assert(result.allowed and result.clearance == 1)
end)

test("fired user is denied", function()
    local result = handlers["auth.check"]({ user = "fired", permission = "auth.manage" })
    assert(not result.allowed and result.reason:find("FIRED"))
end)

test("trusted node can list users", function()
    local result, err = handlers["auth.users.list"]({ actor = "admin" }, { source = "terminal" })
    assert(not err and result.total == 3)
end)

test("spoofed actor is rejected", function()
    local result, err = handlers["auth.users.list"]({ actor = "admin" }, { source = "intruder" })
    assert(not result and err:find("Untrusted"))
end)

test("management persists and keeps backup", function()
    local result, err = handlers["auth.user.set"]({
        actor = "admin",
        target = { name = "visitor", clearance = "CL0", role = "Visitor", status = "Active" },
    }, { source = "terminal" })
    assert(not err and result.name == "visitor")
    assert(files["/cookieos-data/users.db"])
    assert(files["/cookieos-data/users.db.bak"])
end)

test("session is bound to source node", function()
    local challenge = handlers["auth.session.challenge"]({ user = "admin" }, { source = "terminal" })
    local verifier = challenge.salt .. ":test-password"
    for _ = 1, challenge.rounds do verifier = Sha256.hex(verifier .. ":" .. challenge.salt) end
    local opened, err = handlers["auth.session.open"]({
        user = "admin", nonce = challenge.nonce,
        proof = Sha256.hmac(verifier, challenge.nonce .. ":terminal"),
    }, { source = "terminal" })
    assert(not err and opened.token)
    local valid = handlers["auth.session.validate"]({ session = opened.token }, { source = "terminal" })
    assert(valid.user == "admin")
    local delegated = handlers["auth.authorize"]({
        session = opened.token, origin = "terminal", permission = "players.where",
    }, { source = "tracker" })
    assert(delegated.allowed and delegated.user == "admin")
    local invalid, invalidError = handlers["auth.session.validate"]({ session = opened.token }, { source = "intruder" })
    assert(not invalid and invalidError)
    local loggedOut = handlers["auth.session.logout"]({ session = opened.token }, { source = "terminal" })
    assert(loggedOut.loggedOut)
end)

print("All " .. passed .. " auth tests passed")
