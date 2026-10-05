local service = {}
local Sha256 = require("cookieos.crypto.sha256")

service.manifest = {
    name = "auth", version = "3.1.0",
    provides = {
        "auth.check", "auth.whois", "auth.users.list", "auth.user.set", "auth.user.remove",
        "auth.permission.add", "auth.permission.remove", "auth.credential.set",
        "auth.session.challenge", "auth.session.open", "auth.session.validate", "auth.session.logout", "auth.authorize",
    },
}

local defaultPermissions = {
    ["players.where"] = 1,
    ["players.cache"] = 2,
    ["security.view"] = 1,
    ["security.setLevel"] = 4,
    ["audio.trigger"] = 3,
    ["audio.stop"] = 3,
    ["chat.send"] = 1,
    ["auth.whois"] = 1,
    ["auth.view"] = 4,
    ["auth.manage"] = 5,
    ["maintenance.status"] = 1,
    ["maintenance.nodes"] = 2,
    ["maintenance.services"] = 2,
    ["maintenance.manage"] = 4,
    ["core.shutdown"] = 5,
    ["audit.write"] = 3,
    ["audit.view"] = 4,
    ["events.subscribe"] = 1,
    ["events.view"] = 1,
    ["personnel.view"] = 1,
    ["pairing.manage"] = 5,
    ["updates.manage"] = 5,
    ["updates.view"] = 3,
    ["operations.view"] = 2,
    ["incidents.view"] = 2,
    ["incidents.manage"] = 4,
    ["automation.view"] = 3,
    ["automation.manage"] = 5,
    ["access.view"] = 2,
    ["access.use"] = 1,
    ["access.manage"] = 4,
    ["map.view"] = 1,
    ["map.manage"] = 4,
    ["announcements.send"] = 3,
    ["command.access"] = 6,
    ["command.override"] = 6,
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function normalize(value)
    return tostring(value or ""):lower()
end

local function clearance(value)
    local cleaned = tostring(value or ""):upper():gsub("^CL", "")
    local parsed = tonumber(cleaned)
    if not parsed then return nil end
    return math.max(0, math.min(6, math.floor(parsed)))
end

local function normalizeUser(user)
    user = copy(user or {})
    user.clearance = clearance(user.clearance) or 0
    user.role = tostring(user.role or "Unknown")
    user.status = tostring(user.status or "Active")
    user.aliases = type(user.aliases) == "table" and user.aliases or {}
    user.extraPermissions = type(user.extraPermissions) == "table" and user.extraPermissions or {}
    user.lastSeen = user.lastSeen or "Never"
    user.securityNote = tostring(user.securityNote or "")
    return user
end

function service.register(context)
    local options = context.config.auth or {}
    local dataPath = options.dataPath or "/cookieos-data/users.db"
    local users = {}
    local sessions = {}
    local challenges = {}
    local loginFailures = {}
    local permissions = copy(defaultPermissions)
    for name, required in pairs(options.permissions or {}) do permissions[name] = required end

    local function commandUnlocked()
        local command = context.config.commandAuthority or {}
        if not command.required then return true end
        local authorities = { command.node }
        for _, peer in ipairs(command.peers or {}) do if peer ~= command.node then authorities[#authorities + 1] = peer end end
        local available, unlocked = 0, 0
        for _, authority in ipairs(authorities) do
            local response
            if context.network.requestTo then response = context.network:requestTo(authority, "command.status", {}, 2)
            else response = context.network:request("command.status", {}, 2) end
            if response and response.ok and response.data.authority == authority then
                available = available + 1
                if response.data.locked then
                    for token in pairs(sessions) do sessions[token] = nil end
                    return nil, "GLOBAL LOCKDOWN: " .. tostring(response.data.reason or "Command authentication failure")
                end
                unlocked = unlocked + 1
            end
        end
        local quorum = math.max(1, tonumber(command.quorum) or 1)
        if available < quorum or unlocked < quorum then return nil, "Command Authority quorum unavailable; facility access is locked" end
        return true
    end

    local function audit(action, fields)
        if context.audit then context.audit.write(action, fields) end
    end

    local function findUser(name)
        local wanted = normalize(name)
        for canonical, user in pairs(users) do
            if normalize(canonical) == wanted then return canonical, user end
            for _, alias in ipairs(user.aliases) do
                if normalize(alias) == wanted then return canonical, user end
            end
        end
    end

    local function passwordHash(password, salt, rounds)
        local value = tostring(salt) .. ":" .. tostring(password)
        for _ = 1, rounds do value = Sha256.hex(value .. ":" .. salt) end
        return value
    end

    local function setCredential(user, password)
        local rounds = tonumber(options.passwordRounds) or 64
        local salt = Sha256.hex(table.concat({ context.config.node, os.epoch("utc"), math.random(), math.random() }, ":")):sub(1, 32)
        user.credential = { salt = salt, rounds = rounds, hash = passwordHash(password, salt, rounds) }
        user.password = nil
    end

    local function normalizeCredentials(user)
        if type(user.password) == "string" and user.password ~= "" then setCredential(user, user.password) end
        if type(user.credential) ~= "table" then user.credential = nil end
        return user
    end

    local function save()
        local directory = fs.getDir(dataPath)
        if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
        local temporary = dataPath .. ".new"
        local backup = dataPath .. ".bak"
        local handle = fs.open(temporary, "w")
        if not handle then return nil, "Cannot open auth temporary file" end
        handle.write(textutils.serialize({ version = 1, users = users }))
        handle.close()

        if fs.exists(backup) then fs.delete(backup) end
        if fs.exists(dataPath) then fs.move(dataPath, backup) end
        local ok, moveError = pcall(fs.move, temporary, dataPath)
        if not ok then
            if fs.exists(backup) and not fs.exists(dataPath) then fs.move(backup, dataPath) end
            return nil, tostring(moveError)
        end
        return true
    end

    local function loadSerialized(path)
        if not path or not fs.exists(path) then return nil end
        local handle = fs.open(path, "r")
        if not handle then return nil end
        local raw = handle.readAll()
        handle.close()
        local ok, result = pcall(textutils.unserialize, raw)
        if ok and type(result) == "table" then return result end
    end

    local function load()
        local stored = loadSerialized(dataPath)
        local initialize = not stored
        if stored then
            users = stored.users or stored
        else
            users = copy(options.seedUsers or {})
        end
        for name, user in pairs(users) do users[name] = normalizeCredentials(normalizeUser(user)) end
        if initialize then
            local ok, err = save()
            if not ok then error("Cannot initialize auth database: " .. tostring(err)) end
        end
    end

    local function isFired(user)
        return user and normalize(user.status) == "fired"
    end

    local function hasPermission(user, permission)
        if not user or isFired(user) then return false end
        for _, extra in ipairs(user.extraPermissions) do
            if extra == "all" or extra == permission then return true end
        end
        return user.clearance >= (tonumber(permissions[permission]) or 5)
    end

    local function check(username, permission)
        local canonical, user = findUser(username)
        local required = tonumber(permissions[permission]) or 5
        if not user then return false, { reason = "Unknown user", requiredClearance = required } end
        if isFired(user) then
            return false, { reason = user.securityNote ~= "" and user.securityNote or "User is FIRED", user = canonical, requiredClearance = required }
        end
        local allowed = hasPermission(user, permission)
        return allowed, {
            reason = allowed and "Allowed" or ("Requires CL" .. required),
            user = canonical,
            clearance = user.clearance,
            clearanceLabel = "CL" .. user.clearance,
            requiredClearance = required,
            role = user.role,
            status = user.status,
        }
    end

    local function caller(payload, packet)
        local token = payload and payload.session
        local session = token and sessions[token]
        if session then
            if session.expiresAt <= os.epoch("utc") then sessions[token] = nil; return nil end
            if not packet or session.node ~= packet.source then return nil end
            session.lastSeen = os.epoch("utc")
            return session.user
        end
        local claimed = tostring(payload and payload.actor or "")
        if packet and packet.localRequest and packet.source == context.config.node then return claimed end
        local trusted = packet and options.trustedNodes and options.trustedNodes[packet.source]
        if trusted == "*" then return claimed end
        if type(trusted) == "string" and (claimed == "" or normalize(claimed) == normalize(trusted)) then return trusted end
        return nil
    end

    local function authorizeCall(payload, packet, permission)
        local unlocked, lockdownReason = commandUnlocked()
        if not unlocked then return nil, lockdownReason end
        local actor = caller(payload, packet)
        if not actor or actor == "" then return nil, "Untrusted or missing actor identity" end
        local allowed, details = check(actor, permission)
        if not allowed then return nil, details.reason end
        return actor
    end

    local function publicUser(name, user)
        local effectivePermissions = {}
        for permission in pairs(permissions) do
            if hasPermission(user, permission) then table.insert(effectivePermissions, permission) end
        end
        for _, permission in ipairs(user.extraPermissions) do
            if permission == "all" then
                table.insert(effectivePermissions, "all")
            elseif not permissions[permission] then
                table.insert(effectivePermissions, permission)
            end
        end
        table.sort(effectivePermissions)
        return {
            name = name, clearance = user.clearance, clearanceLabel = "CL" .. user.clearance,
            role = user.role, status = user.status, aliases = copy(user.aliases),
            lastSeen = user.lastSeen, securityNote = user.securityNote,
            extraPermissions = copy(user.extraPermissions),
            permissions = effectivePermissions,
        }
    end

    load()

    context.auth = {
        check = check,
        authorize = function(actor, permission)
            local allowed, details = check(actor, permission)
            return allowed, details.reason, details
        end,
        authorizeRequest = function(payload, packet, permission)
            local unlocked, lockdownReason = commandUnlocked()
            if not unlocked then return false, lockdownReason end
            local actor = caller(payload, packet)
            if not actor or actor == "" then return false, "Untrusted or missing actor identity" end
            local allowed, details = check(actor, permission)
            return allowed, details.reason, details
        end,
        listUsers = function()
            local result = {}
            for name, user in pairs(users) do table.insert(result, publicUser(name, user)) end
            table.sort(result, function(a, b)
                if a.clearance ~= b.clearance then return a.clearance > b.clearance end
                return normalize(a.name) < normalize(b.name)
            end)
            return result
        end,
    }

    context.network:provide("auth.check", function(payload)
        local allowed, details = check(payload and (payload.user or payload.username), payload and (payload.permission or payload.perm))
        details.allowed = allowed
        return details
    end)

    context.network:provide("auth.session.challenge", function(payload, packet)
        local unlocked, lockdownReason = commandUnlocked()
        if not unlocked then return nil, lockdownReason end
        local now = os.epoch("utc")
        local challengeCount = 0
        for nonce, challenge in pairs(challenges) do
            if challenge.expiresAt <= now then challenges[nonce] = nil else challengeCount = challengeCount + 1 end
        end
        if challengeCount >= 128 then return nil, "Login service busy" end
        local username = payload and (payload.user or payload.username)
        local name, user = findUser(username)
        local source = packet and packet.source or "unknown"
        local rounds = user and user.credential and user.credential.rounds or (options.passwordRounds or 64)
        local salt = user and user.credential and user.credential.salt
            or Sha256.hex("unknown:" .. normalize(username) .. ":" .. context.config.node):sub(1, 32)
        local nonce = Sha256.hex(table.concat({ source, now, math.random(), math.random() }, ":"))
        challenges[nonce] = { user = name, requested = username, node = source, expiresAt = now + 30000 }
        return { nonce = nonce, salt = salt, rounds = rounds }
    end)

    context.network:provide("auth.session.open", function(payload, packet)
        local username = payload and (payload.user or payload.username)
        local source = packet and packet.source or "unknown"
        local nonce = payload and payload.nonce
        local proof = tostring(payload and payload.proof or "")
        local challenge = nonce and challenges[nonce]
        challenges[nonce] = nil
        local name, user = findUser(username)
        local failureKey = source .. ":" .. normalize(username)
        local failure = loginFailures[failureKey]
        local now = os.epoch("utc")
        if failure and failure.lockedUntil and failure.lockedUntil > now then
            return nil, "Login temporarily locked"
        end
        local expected = user and user.credential and nonce and Sha256.hmac(user.credential.hash, nonce .. ":" .. source)
        if not challenge or challenge.node ~= source or challenge.expiresAt <= now
            or normalize(challenge.requested) ~= normalize(username)
            or not user or isFired(user) or not user.credential or proof ~= expected then
            failure = failure or { count = 0 }
            failure.count = failure.count + 1
            if failure.count >= (options.maxLoginFailures or 5) then
                failure.lockedUntil = now + ((options.loginLockSeconds or 30) * 1000)
                failure.count = 0
            end
            loginFailures[failureKey] = failure
            audit("auth.login", { node = source, actor = tostring(username or "unknown"), outcome = "denied" })
            return nil, "Invalid credentials"
        end
        loginFailures[failureKey] = nil
        local token = Sha256.hmac(context.config.identity.nodeKey or tostring(math.random()), table.concat({
            name, source, now, math.random(), math.random(),
        }, ":"))
        local expiresAt = now + ((options.sessionSeconds or 1800) * 1000)
        sessions[token] = { user = name, node = source, createdAt = now, lastSeen = now, expiresAt = expiresAt }
        audit("auth.login", { node = source, actor = name })
        return { token = token, user = name, role = user.role, clearance = user.clearance, expiresAt = expiresAt }
    end)

    context.network:provide("auth.session.validate", function(payload, packet)
        local name = caller(payload, packet)
        if not name then return nil, "Invalid or expired session" end
        local _, user = findUser(name)
        return { user = name, role = user.role, clearance = user.clearance }
    end)

    context.network:provide("auth.authorize", function(payload, packet)
        if not packet or not options.delegates or options.delegates[packet.source] ~= true then
            return nil, "Node is not an authorization delegate"
        end
        local session = payload and payload.session and sessions[payload.session]
        local now = os.epoch("utc")
        if not session or session.expiresAt <= now or session.node ~= payload.origin then
            return { allowed = false, reason = "Invalid or expired delegated session" }
        end
        local allowed, details = check(session.user, payload.permission)
        details.allowed = allowed
        details.user = session.user
        return details
    end)

    context.network:provide("auth.session.logout", function(payload, packet)
        local token = payload and payload.session
        local session = token and sessions[token]
        if not session or not packet or session.node ~= packet.source then return nil, "Invalid session" end
        sessions[token] = nil
        audit("auth.logout", { node = packet.source, actor = session.user })
        return { loggedOut = true }
    end)

    context.network:provide("auth.whois", function(payload, packet)
        local actor, err = authorizeCall(payload, packet, "auth.whois")
        if not actor then return nil, err end
        local name, user = findUser(payload.user or payload.name)
        if not user then return nil, "User not found" end
        return publicUser(name, user)
    end)

    context.network:provide("auth.users.list", function(payload, packet)
        local actor, err = authorizeCall(payload, packet, "auth.view")
        if not actor then return nil, err end
        local result = {}
        for name, user in pairs(users) do table.insert(result, publicUser(name, user)) end
        table.sort(result, function(a, b)
            if a.clearance ~= b.clearance then return a.clearance > b.clearance end
            return normalize(a.name) < normalize(b.name)
        end)
        return { users = result, total = #result }
    end)

    context.network:provide("auth.user.set", function(payload, packet)
        local actor, err = authorizeCall(payload, packet, "auth.manage")
        if not actor then return nil, err end
        local target = payload.target or payload
        local name = tostring(target.name or target.user or ""):match("^%s*(.-)%s*$")
        if name == "" or clearance(target.clearance) == nil then return nil, "Name and valid clearance are required" end
        users[name] = normalizeCredentials(normalizeUser(target))
        local ok, saveError = save()
        if not ok then return nil, saveError end
        context.log.info(actor .. " saved auth user " .. name)
        audit("auth.user.set", { actor = actor, details = { user = name, clearance = users[name].clearance } })
        context.publish("auth.user.changed", { action = "set", user = publicUser(name, users[name]), actor = actor })
        return publicUser(name, users[name])
    end)

    context.network:provide("auth.user.remove", function(payload, packet)
        local actor, err = authorizeCall(payload, packet, "auth.manage")
        if not actor then return nil, err end
        local name = findUser((payload.target and (payload.target.name or payload.target.user)) or payload.name or payload.user)
        if not name then return nil, "User not found" end
        users[name] = nil
        local ok, saveError = save()
        if not ok then return nil, saveError end
        context.log.info(actor .. " removed auth user " .. name)
        audit("auth.user.remove", { actor = actor, details = { user = name } })
        context.publish("auth.user.changed", { action = "remove", user = name, actor = actor })
        return { removed = name }
    end)

    local function changePermission(payload, packet, remove)
        local actor, err = authorizeCall(payload, packet, "auth.manage")
        if not actor then return nil, err end
        local target = payload.target or payload
        local name, user = findUser(target.name or target.user)
        local permission = tostring(target.permission or "")
        if not user then return nil, "User not found" end
        if permission == "" then return nil, "Permission is required" end
        local found
        for index = #user.extraPermissions, 1, -1 do
            if user.extraPermissions[index] == permission then
                found = true
                if remove then table.remove(user.extraPermissions, index) end
            end
        end
        if not remove and not found then table.insert(user.extraPermissions, permission) end
        if remove and not found then return nil, "Permission not found" end
        local ok, saveError = save()
        if not ok then return nil, saveError end
        context.log.info(actor .. (remove and " removed " or " added ") .. permission .. (remove and " from " or " to ") .. name)
        audit(remove and "auth.permission.remove" or "auth.permission.add", {
            actor = actor, details = { user = name, permission = permission },
        })
        context.publish("auth.user.changed", { action = remove and "permission.remove" or "permission.add", user = name, actor = actor })
        return publicUser(name, user)
    end

    context.network:provide("auth.permission.add", function(payload, packet) return changePermission(payload, packet, false) end)
    context.network:provide("auth.permission.remove", function(payload, packet) return changePermission(payload, packet, true) end)

    context.network:provide("auth.credential.set", function(payload, packet)
        local actor, err = authorizeCall(payload, packet, "auth.manage")
        if not actor then return nil, err end
        local target = payload.target or payload
        local name, user = findUser(target.name or target.user)
        local password = tostring(target.password or "")
        if not user then return nil, "User not found" end
        if #password < 4 then return nil, "Password must be at least 4 characters" end
        setCredential(user, password)
        for token, session in pairs(sessions) do
            if session.user == name then sessions[token] = nil end
        end
        local ok, saveError = save()
        if not ok then return nil, saveError end
        context.log.info(actor .. " changed credentials for " .. name)
        audit("auth.credential.set", { actor = actor, details = { user = name } })
        return { user = name, credentialUpdated = true }
    end)
end

return service
