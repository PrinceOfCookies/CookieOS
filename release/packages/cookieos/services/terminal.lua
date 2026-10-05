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
    print("  useradd <user> <0-5> [role]  Create a normal login")
    print("  userdel <user>        Delete a login")
    print("  permadd <user> <permission>   Grant a permission")
    print("  permdel <user> <permission>   Revoke a permission")
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
    print("  sound [name]          Play a sound in a speaker zone")
    print("  alarm [count]         Trigger the speaker-zone alarm")
    print("  audiostop             Stop speaker playback")
    print("  chat [status] | chat [#channel] <message>  Send through the Chat Gateway")
    print("  announce <normal|urgent|emergency> <message>")
    print("  dashboard [monitor]  Operations overview")
    print("  incidents [status]   List incidents")
    print("  incident open <severity> <title>")
    print("  incident update <id> <status> [note]")
    print("  doors                List access-controlled doors")
    print("  door <id|zone> <lock|unlock>  Control doors")
    print("  map [monitor]        Show the editable facility map")
    print("  room set <id> <floor> <x> <y> <w> <h> [name]")
    print("  room remove <id>     Remove a map room")
    print("  rules                List automation rules")
    print("  rule run <id>        Run an automation rule")
    print("  rule set <id> <topic> <lock|unlock|alarm> <target>")
    print("  fleet                Show rollout plans")
    print("  fleet status <node>  Show a node's update state")
    print("  fleet stage <node> [ref] | apply <node> | rollback <node>")
    print("  console               Open graphical Command Center")
    print("  passissue <CL> [seconds] | passlogin <code>")
    print("  userpolicy <user> <zones|*> [expiry-epoch]")
    print("  credrevoke <user>      Revoke lost credentials")
    print("  forcepasswd <user>     Require a password change")
    print("  approve request <action> | approve <id>")
    print("  policies | policy <id>")
    print("  alarms | alarmx <pattern> [message] | drill <pattern>")
    print("  devices | devname <peripheral> <label>")
    print("  workflows | workflow <id> | step <run-id>")
    print("  notify <info|notice|warning|critical|emergency> <message>")
    print("  tasks | task <id> <owner> <title> | taskdone <id>")
    print("  patrol <route> <checkpoint>")
    print("  sim <start|stop|status> [name]")
    print("  auditfind <query> | auditverify | auditexport [path]")
    print("  extensions | ext <name> <action> [data]")
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

local function withMonitor(draw)
    local monitor = peripheral.find("monitor")
    if not monitor then printError("No attached monitor was found."); return end
    local previous = term.current()
    local ok, err = pcall(function()
        monitor.setTextScale(0.5); term.redirect(monitor); term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white); term.clear(); term.setCursorPos(1, 1); draw(monitor.getSize())
    end)
    term.redirect(previous)
    if not ok then printError("Monitor display failed: " .. tostring(err)) end
end

local function responseData(response, err)
    if not response then printError(friendlyError(err)); return nil end
    if not response.ok then printError(friendlyError(response.error)); return nil end
    return response.data
end

function service.register(context)
    local session
    local sessionUser
    local commandState

    context.network:on("event", function(packet)
        if packet.service == "command.lockdown" and type(packet.payload) == "table"
            and packet.source == context.config.commandAuthority.node then commandState = packet.payload end
    end)

    local function commandAllowsLogin()
        local options = context.config.commandAuthority or {}
        if not options.required then return true end
        local response, err
        if context.network.requestTo then response, err = context.network:requestTo(options.node, "command.status", {}, 2)
        else response, err = context.network:request("command.status", {}, 2) end
        if not response or not response.ok then return nil, "Command Authority unavailable; terminal login is locked" end
        commandState = response.data
        if commandState.authority ~= options.node then return nil, "Unexpected Command Authority identity" end
        if commandState.locked then return nil, "GLOBAL LOCKDOWN: " .. tostring(commandState.reason or "Command authentication failure") end
        return true
    end

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
                local loginAllowed, commandError = commandAllowsLogin()
                if not loginAllowed then printError(commandError)
                else
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
            elseif (command == "permadd" or command == "permdel") and words[2] and words[3] then
                local endpoint = command == "permadd" and "auth.permission.add" or "auth.permission.remove"
                printResponse(context.network:request(endpoint, authorized({ user = words[2], permission = words[3] })))
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
            elseif command == "sound" then
                printResponse(context.network:request("audio.sound", authorized({ sound = words[2] })))
            elseif command == "alarm" then
                printResponse(context.network:request("audio.alarm", authorized({ count = tonumber(words[2]) or 3 })))
            elseif command == "audiostop" then
                printResponse(context.network:request("audio.stop", authorized()))
            elseif command == "chat" and words[2] == "status" then
                printResponse(context.network:request("chat.status", authorized()))
            elseif command == "chat" and words[2] then
                local channel, start = "global", 2
                if words[2]:sub(1, 1) == "#" then channel, start = words[2]:sub(2), 3 end
                printResponse(context.network:request("chat.send", authorized({ channel = channel, message = table.concat(words, " ", start) })))
            elseif command == "announce" and words[2] and words[3] then
                printResponse(context.network:request("audio.announce", authorized({ priority = words[2], message = table.concat(words, " ", 3) })))
            elseif command == "dashboard" then
                local response, err = context.network:request("ops.snapshot", authorized())
                local data = responseData(response, err)
                if data and tostring(words[2] or ""):lower() == "monitor" then withMonitor(function()
                    print("COOKIESECURITY OPERATIONS"); print("Generated: " .. tostring(data.generatedAt)); print("")
                    print("Nodes: " .. #data.nodes .. "  Incidents: " .. data.openIncidents .. " open")
                    print("Doors: " .. tostring((function()local n=0 for _ in pairs(data.doors or{})do n=n+1 end return n end)()) .. "  Rooms: " .. data.rooms)
                    print(""); for _, node in ipairs(data.nodes) do print(string.format("%-18s %-7s %3ss %s", node.node, node.mode or "?", node.age or 0, node.location or "")) end
                end) elseif data then print(textutils.serialize(data, { compact = true })) end
            elseif command == "incidents" then
                printResponse(context.network:request("incident.list", authorized({ status = words[2] })))
            elseif command == "incident" and words[2] == "open" and words[3] and words[4] then
                printResponse(context.network:request("incident.open", authorized({ severity = words[3], title = table.concat(words, " ", 4) })))
            elseif command == "incident" and words[2] == "update" and words[3] and words[4] then
                printResponse(context.network:request("incident.update", authorized({ id = words[3], status = words[4], note = #words > 4 and table.concat(words, " ", 5) or nil })))
            elseif command == "doors" then
                printResponse(context.network:request("access.list", authorized()))
            elseif command == "door" and words[2] and (words[3] == "lock" or words[3] == "unlock") then
                local selector = words[2]; local fields = { locked = words[3] == "lock" }
                if selector:sub(1, 1) == "@" then fields.zone = selector:sub(2) else fields.id = selector end
                printResponse(context.network:request("access.set", authorized(fields)))
            elseif command == "map" then
                local response, err = context.network:request("map.get", authorized())
                local data = responseData(response, err)
                if data and tostring(words[2] or ""):lower() == "monitor" then withMonitor(function(width, height)
                    print("FACILITY MAP")
                    for _, room in pairs(data.rooms or {}) do
                        local x, y = math.max(1, room.x), math.max(2, room.y + 1)
                        if x <= width and y <= height then term.setCursorPos(x, y); term.setBackgroundColor(room.color or colors.gray); write((room.name or room.id):sub(1, math.min(room.width or 5, width - x + 1))); term.setBackgroundColor(colors.black) end
                    end
                end) elseif data then print(textutils.serialize(data, { compact = true })) end
            elseif command == "room" and words[2] == "set" and words[3] and words[8] then
                printResponse(context.network:request("map.room.set", authorized({ id=words[3], floor=tonumber(words[4]), x=tonumber(words[5]), y=tonumber(words[6]), width=tonumber(words[7]), height=tonumber(words[8]), name=#words>8 and table.concat(words," ",9) or words[3] })))
            elseif command == "room" and words[2] == "remove" and words[3] then
                printResponse(context.network:request("map.room.remove", authorized({ id = words[3] })))
            elseif command == "rules" then
                printResponse(context.network:request("automation.list", authorized()))
            elseif command == "rule" and words[2] == "run" and words[3] then
                printResponse(context.network:request("automation.run", authorized({ id = words[3] })))
            elseif command == "rule" and words[2] == "set" and words[3] and words[5] then
                local action = words[5]; local specification
                if action == "lock" or action == "unlock" then specification = { type = action .. "-zone", zone = words[6] or "all" }
                elseif action == "alarm" then specification = { type = "alarm", count = tonumber(words[6]) or 3 }
                else specification = { type = action, message = #words > 5 and table.concat(words, " ", 6) or "Automated alert" } end
                printResponse(context.network:request("automation.set", authorized({ id = words[3], topic = words[4], actions = { specification } })))
            elseif command == "fleet" and words[2] == "status" and words[3] then
                printResponse(context.network:requestTo(words[3], "fleet.agent.status", authorized()))
            elseif command == "fleet" and words[2] == "stage" and words[3] then
                printResponse(context.network:requestTo(words[3], "fleet.agent.stage", authorized({ ref = words[4] or "cookieos-v3-rewrite" }), 120))
            elseif command == "fleet" and words[2] == "apply" and words[3] then
                printResponse(context.network:requestTo(words[3], "fleet.agent.apply", authorized(), 10))
            elseif command == "fleet" and words[2] == "rollback" and words[3] then
                printResponse(context.network:requestTo(words[3], "fleet.agent.rollback", authorized(), 10))
            elseif command == "fleet" then
                printResponse(context.network:request("fleet.status", authorized()))
            elseif command == "console" then
                if not session then printError("Run login first.") else local ok,err=require("cookieos.ui.command_center").run(context,authorized,words[2]);if not ok then printError(err)end end
            elseif command == "passissue" and tonumber(words[2]) then
                printResponse(context.network:request("auth.pass.issue",authorized({clearance=tonumber(words[2]),seconds=tonumber(words[3])or 3600})))
            elseif command == "passlogin" and words[2] then
                local response,err=context.network:request("auth.pass.redeem",{code=words[2]});if response and response.ok then session=response.data.token;sessionUser=response.data.user;print("Visitor pass accepted as "..sessionUser)else printResponse(response,err)end
            elseif command == "userpolicy" and words[2] and words[3] then
                local zones={};for zone in words[3]:gmatch("[^,]+")do zones[#zones+1]=zone end;printResponse(context.network:request("auth.user.policy",authorized({user=words[2],zones=zones,expiresAt=tonumber(words[4])})))
            elseif command == "credrevoke" and words[2] then printResponse(context.network:request("auth.credential.revoke",authorized({user=words[2]})))
            elseif command == "forcepasswd" and words[2] then printResponse(context.network:request("auth.user.policy",authorized({user=words[2],mustChangePassword=true})))
            elseif command == "approve" and words[2] == "request" and words[3] then
                printResponse(context.network:request("auth.approval.request",authorized({action=table.concat(words," ",3)})))
            elseif command == "approve" and words[2] then
                printResponse(context.network:request("auth.approval.approve",authorized({id=words[2]})))
            elseif command == "policies" then printResponse(context.network:request("policy.list",authorized()))
            elseif command == "policy" and words[2] then printResponse(context.network:request("policy.apply",authorized({id=words[2],approval=words[3]})))
            elseif command == "alarms" then printResponse(context.network:request("alarm.list",authorized()))
            elseif command == "alarmx" and words[2] then printResponse(context.network:request("alarm.trigger",authorized({pattern=words[2],message=#words>2 and table.concat(words," ",3)or nil})))
            elseif command == "drill" and words[2] then printResponse(context.network:request("alarm.drill",authorized({pattern=words[2],message=#words>2 and table.concat(words," ",3)or nil})))
            elseif command == "devices" then printResponse(context.network:request("device.list",authorized()))
            elseif command == "devname" and words[2] and words[3] then printResponse(context.network:request("device.rename",authorized({name=words[2],label=table.concat(words," ",3)})))
            elseif command == "workflows" then printResponse(context.network:request("workflow.list",authorized()))
            elseif command == "workflow" and words[2] then printResponse(context.network:request("workflow.start",authorized({id=words[2],owner=sessionUser})))
            elseif command == "step" and words[2] then printResponse(context.network:request("workflow.advance",authorized({id=words[2]})))
            elseif command == "notify" and words[2] and words[3] then printResponse(context.network:request("notify.send",authorized({severity=words[2],message=table.concat(words," ",3),channels={"monitor","chat"}})))
            elseif command == "tasks" then printResponse(context.network:request("task.list",authorized()))
            elseif command == "task" and words[2] and words[3] and words[4] then printResponse(context.network:request("task.set",authorized({id=words[2],owner=words[3],title=table.concat(words," ",4)})))
            elseif command == "taskdone" and words[2] then printResponse(context.network:request("task.update",authorized({id=words[2],status="complete"})))
            elseif command == "patrol" and words[2] and words[3] then printResponse(context.network:request("patrol.checkpoint",authorized({route=words[2],checkpoint=words[3]})))
            elseif command == "sim" and words[2] == "start" then printResponse(context.network:request("simulation.start",authorized({name=#words>2 and table.concat(words," ",3)or"Exercise"})))
            elseif command == "sim" and words[2] == "stop" then printResponse(context.network:request("simulation.stop",authorized({outcome=#words>2 and table.concat(words," ",3)or"completed"})))
            elseif command == "sim" then printResponse(context.network:request("simulation.status",authorized()))
            elseif command == "auditfind" and words[2] then printResponse(context.network:request("audit.query",authorized({query=table.concat(words," ",2),limit=100})))
            elseif command == "auditverify" then printResponse(context.network:request("audit.verify",authorized()))
            elseif command == "auditexport" then printResponse(context.network:request("audit.export",authorized({path=words[2]})))
            elseif command == "extensions" then printResponse(context.network:request("extension.list",authorized()))
            elseif command == "ext" and words[2] and words[3] then printResponse(context.network:request("extension.call",authorized({extension=words[2],action=words[3],data=#words>3 and table.concat(words," ",4)or nil})))
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
