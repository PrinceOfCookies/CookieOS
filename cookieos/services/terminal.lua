local service = {}
local Sha256 = require("cookieos.crypto.sha256")

service.manifest = {
    name = "terminal", version = "3.1.0", provides = {},
}

local function printHelp()
    print("CookieOS terminal commands:")
    print("  help                  Show this help")
    print("  routes                List discovered nodes")
    print("  services              List discovered services")
    print("  ping <node>           Ping a node")
    print("  security              Read the security level")
    print("  security <level>      Set GREEN/YELLOW/RED/BLACK")
    print("  whois <user>          Show an auth user")
    print("  users                 List auth users")
    print("  useradd <user> <0-5> [role]  Create a login")
    print("  userdel <user>        Delete a login")
    print("  login [user]          Open an authenticated session")
    print("  logout                Revoke the current session")
    print("  whoami                Show the terminal identity")
    print("  passwd [user]         Set a user's login password")
    print("  where <player>        Locate a player")
    print("  maint                 Show maintenance status")
    print("  nodes                 List known nodes")
    print("  audit [limit]         Show recent audit records")
    print("  personnel [filter]    List personnel")
    print("  psearch <query>       Search personnel")
    print("  topics                List event topics")
    print("  paircode              Authority creates a 16-character pairing code")
    print("  revoke <node>         Revoke a paired node")
    print("  sound [name]          Play a sound in a speaker zone")
    print("  alarm [count]         Trigger the speaker-zone alarm")
    print("  audiostop             Stop speaker playback")
    print("  chat <message>        Send through the chat gateway")
end

local function friendlyError(message)
    message = tostring(message or "Request failed")
    if message == "Untrusted or missing actor identity" then
        return "Authentication required. Run 'login [user]' first, then retry the command. Pair this node first if it cannot reach the authority."
    end
    if message:find("expired session", 1, true) or message == "Invalid session" then
        return "Your login session expired. Run 'login [user]' again."
    end
    return message
end

local function printResponse(response, err)
    if not response then printError(friendlyError(err or "No response")); return end
    if not response.ok then printError(friendlyError(response.error)); return end
    print(textutils.serialize(response.data, { compact = true }))
end

local function printHelpOnMonitor()
    local monitor = peripheral.find("monitor")
    if not monitor then printError("No attached monitor was found."); return end
    local previous = term.current()
    local ok, err = pcall(function()
        monitor.setTextScale(0.5)
        term.redirect(monitor)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1, 1)
        printHelp()
    end)
    term.redirect(previous)
    if not ok then printError("Could not display help on monitor: " .. tostring(err)); return end
    print("Help displayed on attached monitor.")
end

function service.register(context)
    local session
    local sessionUser

    local function authorized(fields)
        fields = fields or {}
        if session then fields.session = session else fields.actor = context.config.identity.user end
        return fields
    end

    local function passwordHash(password, salt, rounds)
        local value = tostring(salt) .. ":" .. tostring(password)
        for _ = 1, rounds do value = Sha256.hex(value .. ":" .. salt) end
        return value
    end

    context.supervisor:add("terminal", function()
        print("CookieOS v3 terminal on " .. context.config.node)
        print("Type 'help' for commands or 'help monitor' to display them on an attached monitor.")
        print("Run 'login [user]' before using protected commands.")

        while true do
            term.setTextColor(colors.yellow)
            write("cookieos> ")
            term.setTextColor(colors.white)
            local input = read()
            local words = {}
            for word in tostring(input):gmatch("%S+") do table.insert(words, word) end
            local command = tostring(words[1] or ""):lower()

            if command == "help" then
                if tostring(words[2] or ""):lower() == "monitor" then printHelpOnMonitor() else printHelp() end
            elseif command == "login" then
                local username = words[2] or context.config.identity.user
                if not username then
                    write("User: ")
                    username = read()
                end
                write("Password: ")
                local password = read("*")
                local challenge, challengeError = context.network:request("auth.session.challenge", { user = username })
                local response, err
                if challenge and challenge.ok then
                    local data = challenge.data
                    local verifier = passwordHash(password, data.salt, data.rounds)
                    response, err = context.network:request("auth.session.open", {
                        user = username,
                        nonce = data.nonce,
                        proof = Sha256.hmac(verifier, data.nonce .. ":" .. context.config.node),
                    })
                else
                    response, err = challenge, challengeError
                end
                if response and response.ok then
                    session = response.data.token
                    sessionUser = response.data.user
                    print("Logged in as " .. sessionUser)
                else
                    printResponse(response, err)
                end
            elseif command == "logout" then
                if session then printResponse(context.network:request("auth.session.logout", { session = session })) end
                session, sessionUser = nil, nil
                print("Logged out")
            elseif command == "whoami" then
                print(sessionUser or context.config.identity.user or "anonymous")
            elseif command == "passwd" then
                local target = words[2] or sessionUser or context.config.identity.user
                if not target then
                    printError("No target user")
                else
                    write("New password: ")
                    local password = read("*")
                    printResponse(context.network:request("auth.credential.set", authorized({
                        target = { user = target, password = password },
                    })))
                end
            elseif command == "useradd" then
                local username = words[2]
                local level = tonumber(words[3])
                local role = #words >= 4 and table.concat(words, " ", 4) or "User"
                if not username or not level or level < 0 or level > 5 or level ~= math.floor(level) then
                    printError("Usage: useradd <user> <clearance 0-5> [role]")
                else
                    write("Password for " .. username .. ": ")
                    local password = read("*")
                    write("Confirm password: ")
                    local confirmation = read("*")
                    if #password < 4 then printError("Password must be at least 4 characters")
                    elseif password ~= confirmation then printError("Passwords do not match")
                    else
                        local response, err = context.network:request("auth.user.set", authorized({ target = {
                            name = username, clearance = level, role = role, status = "Active",
                            extraPermissions = {}, password = password,
                        } }))
                        if response and response.ok then print("Created login " .. username .. " (CL" .. level .. ", " .. role .. ")")
                        else printResponse(response, err) end
                    end
                end
            elseif command == "userdel" then
                local username = words[2]
                if not username then printError("Usage: userdel <user>")
                elseif sessionUser and username:lower() == sessionUser:lower() then printError("You cannot delete your currently logged-in account")
                else
                    write("Delete login " .. username .. "? [y/N] ")
                    local confirmation = read():lower()
                    if confirmation == "y" or confirmation == "yes" then
                        local response, err = context.network:request("auth.user.remove", authorized({ user = username }))
                        if response and response.ok then print("Deleted login " .. tostring(response.data.removed))
                        else printResponse(response, err) end
                    else print("Cancelled") end
                end
            elseif command == "where" and words[2] then
                printResponse(context.network:request("players.lookup", authorized({ query = words[2] })))
            elseif command == "maint" then
                printResponse(context.network:request("maintenance.status", authorized()))
            elseif command == "nodes" then
                printResponse(context.network:request("maintenance.nodes", authorized()))
            elseif command == "audit" then
                printResponse(context.network:request("audit.query", authorized({ limit = tonumber(words[2]) or 20 })))
            elseif command == "personnel" then
                printResponse(context.network:request("personnel.list", authorized({ filter = words[2] or "all" })))
            elseif command == "psearch" and words[2] then
                printResponse(context.network:request("personnel.search", authorized({ query = table.concat(words, " ", 2) })))
            elseif command == "topics" then
                printResponse(context.network:request("events.topics", authorized()))
            elseif command == "paircode" then
                local response, err = context.network:request("pairing.begin", authorized())
                if not response then printError(friendlyError(err or "No response"))
                elseif not response.ok then printError(friendlyError(response.error))
                else
                    print("Authority-generated pairing code:")
                    print("  " .. tostring(response.data.code))
                    print("Enter this 16-character code on the new node. It expires in about two minutes and can be used once.")
                end
            elseif command == "revoke" and words[2] then
                printResponse(context.network:request("pairing.revoke", authorized({ node = words[2] })))
            elseif command == "sound" then
                printResponse(context.network:request("audio.sound", authorized({ sound = words[2] })))
            elseif command == "alarm" then
                printResponse(context.network:request("audio.alarm", authorized({ count = tonumber(words[2]) or 3 })))
            elseif command == "audiostop" then
                printResponse(context.network:request("audio.stop", authorized()))
            elseif command == "chat" and words[2] then
                printResponse(context.network:request("chat.send", authorized({ message = table.concat(words, " ", 2) })))
            elseif command == "routes" then
                for node, route in pairs(context.network.routes) do
                    print(string.format("%s  %s  %s  %ds", node, route.mode, route.location, math.floor(os.clock() - route.seenAt)))
                end
            elseif command == "services" then
                for node, route in pairs(context.network.routes) do
                    print(node .. ": " .. table.concat(route.services or {}, ", "))
                end
            elseif command == "ping" and words[2] then
                local id = context.network:send("request", {
                    destination = words[2], service = "node.ping", payload = { terminal = context.config.node },
                })
                local timer = os.startTimer(3)
                while true do
                    local event, value, response = os.pullEvent()
                    if event == "cookieos_response" and value == id then printResponse(response); break end
                    if event == "timer" and value == timer then printError("Ping timed out"); break end
                end
            elseif command == "security" then
                local serviceName = words[2] and "security.set" or "security.get"
                local payload = authorized()
                if words[2] then payload.level = words[2] end
                printResponse(context.network:request(serviceName, payload))
            elseif command == "whois" and words[2] then
                printResponse(context.network:request("auth.whois", authorized({ user = words[2] })))
            elseif command == "users" then
                printResponse(context.network:request("auth.users.list", authorized()))
            elseif command ~= "" then
                printError("Unknown command. Type help.")
            end
        end
    end, { restart = true })
end

return service
