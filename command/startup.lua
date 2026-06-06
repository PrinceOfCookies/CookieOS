-- startup.lua
-- SubTerra Command Server
-- Owns chat commands, auth checks, formatted replies, and command routing.

local nodeClient = require("subterra_node_client")

nodeClient.init({
  modemSide = "back",
  protocol = "subterra_core",
  authProtocol = "subterra_auth",
  heartbeatSeconds = 5,
  node = "command_server",
  role = "command",
  location = "Server Room",
  services = {
    "chat.commands",
    "players.where",
    "security.command",
    "auth.whois",
    "personnel.commands",
  }
})

local chatBox = peripheral.find("chat_box")
local monitor = peripheral.find("monitor")
local playerDetector = peripheral.find("player_detector")

if not chatBox then error("No chat box found") end

if monitor then
  monitor.setTextScale(0.5)
end

local playerDataProtocol = "subterra_player_data"
local chatRadius = 30

local stats = {
  commands = 0,
  denied = 0,
  errors = 0,
  lastCommand = "none",
  lastUser = "none",
}

local logs = {}

local function addLog(message)
  table.insert(logs, 1, textutils.formatTime(os.time(), true) .. " " .. tostring(message))

  while #logs > 8 do
    table.remove(logs)
  end
end

local function trimText(text, maxWidth)
  text = tostring(text or "")
  maxWidth = tonumber(maxWidth) or #text

  if #text <= maxWidth then return text end
  if maxWidth <= 3 then return text:sub(1, maxWidth) end

  return text:sub(1, maxWidth - 3) .. "..."
end

local function drawLine(y, text, color)
  if not monitor then return end

  local width, height = monitor.getSize()
  if y < 1 or y > height then return end

  monitor.setCursorPos(1, y)
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(color or colors.white)
  monitor.clearLine()
  monitor.write(trimText(text, width))
end

local function drawCentered(y, text, color, bg)
  if not monitor then return end

  local width = monitor.getSize()
  text = trimText(text, width)

  monitor.setCursorPos(1, y)
  monitor.setBackgroundColor(bg or colors.black)
  monitor.clearLine()

  local x = math.floor((width - #text) / 2) + 1
  monitor.setCursorPos(x, y)
  monitor.setTextColor(color or colors.white)
  monitor.write(text)
end

local function redraw()
  if not monitor then return end

  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()

  monitor.setCursorPos(1, 1)
  monitor.setBackgroundColor(colors.red)
  monitor.clearLine()
  drawCentered(1, "SUBTERRA COMMAND SERVER", colors.white, colors.red)

  drawCentered(3, "Chat Command Router", colors.lime)
  drawLine(5, "Commands: " .. stats.commands .. " | Denied: " .. stats.denied .. " | Errors: " .. stats.errors, colors.lightGray)
  drawLine(6, "Last User: " .. stats.lastUser, colors.lightBlue)
  drawLine(7, "Last Cmd: " .. stats.lastCommand, colors.lightBlue)
  drawLine(8, "Security: " .. nodeClient.getSecurityLevel(), colors.yellow)

  drawLine(10, "Logs", colors.yellow)

  local y = 11
  for _, line in ipairs(logs) do
    drawLine(y, line, colors.lightGray)
    y = y + 1
  end
end

local function flattenFormattedParts(parts)
  local plain = {}

  for _, part in ipairs(parts) do
    table.insert(plain, tostring(part.text or ""))
  end

  return table.concat(plain)
end

local function sendPlainChat(message)
  local text = tostring(message)

  local ok = pcall(function()
    chatBox.sendMessage(text, "&4&lSentinel", "<>", "&8", chatRadius)
  end)

  if not ok then
    pcall(chatBox.sendMessage, "<Sentinel> " .. text)
  end
end

local function sendFormattedChat(parts)
  local plain = flattenFormattedParts(parts)

  if type(chatBox.sendFormattedMessage) == "function" then
    local ok = pcall(function()
      local json = textutils.serialiseJSON(parts)
      chatBox.sendFormattedMessage(json, "&4&lSentinel", "<>", "&8", chatRadius)
    end)

    if ok then
      return
    end
  end

  sendPlainChat(plain)
end

local function sendFormattedToPlayer(player, parts)
  if type(chatBox.sendFormattedMessageToPlayer) ~= "function" then
    return false
  end

  local ok = pcall(function()
    local json = textutils.serialiseJSON(parts)
    chatBox.sendFormattedMessageToPlayer(json, player, "&4&lSentinel")
  end)

  return ok
end

local function formatCoord(value)
  value = tonumber(value)
  return value and tostring(math.floor(value + 0.5)) or "?"
end

local function formatDimension(dimension)
  dimension = tostring(dimension or "unknown")

  if dimension == "minecraft:overworld" then return "Overworld" end
  if dimension == "minecraft:the_nether" then return "Nether" end
  if dimension == "minecraft:the_end" then return "End" end

  return dimension
end

local function joinList(tbl)
  if type(tbl) ~= "table" or #tbl == 0 then
    return "None"
  end

  return table.concat(tbl, ", ")
end


local authUsers = {
  PrinceOfCookies = {
    aliases = { "prince", "cookies", "poc" },
  },

  lifeline4603 = {
    aliases = { "lifeline", "life" },
  },
}

local function scoreNameMatch(name, input)
  name = tostring(name or "")
  input = tostring(input or ""):lower()

  local lowerName = name:lower()
  local startIndex = lowerName:find(input, 1, true)

  if not startIndex then
    return nil
  end

  -- Lower is better. Exact/prefix/shorter matches naturally win.
  return startIndex + math.abs(#lowerName - #input)
end

local function resolveAuthUser(input)
  input = tostring(input or ""):match("^%s*(.-)%s*$")

  if input == "" then
    return nil, "No name provided"
  end

  local bestName = nil
  local bestScore = nil
  local matches = {}

  for name, data in pairs(authUsers) do
    local score = scoreNameMatch(name, input)

    for _, alias in ipairs(data.aliases or {}) do
      local aliasScore = scoreNameMatch(alias, input)

      if aliasScore and (not score or aliasScore < score) then
        score = aliasScore
      end
    end

    if score then
      table.insert(matches, name)

      if not bestScore or score < bestScore then
        bestName = name
        bestScore = score
      end
    end
  end

  if not bestName then
    return input, nil, {}
  end

  return bestName, nil, matches
end

local function makeRequestId()
  return tostring(os.getComputerID()) .. "-" .. tostring(os.clock()) .. "-" .. tostring(math.random(1000, 9999))
end

local function requestPlayerLookup(query)
  local requestId = makeRequestId()

  rednet.broadcast({
    app = "subterra",
    type = "player_lookup",
    requestId = requestId,
    query = query,
  }, playerDataProtocol)

  local startedAt = os.clock()

  while os.clock() - startedAt < 2.5 do
    local _, packet = rednet.receive(playerDataProtocol, 2.5)

    if type(packet) == "table"
      and packet.app == "subterra"
      and packet.type == "player_lookup_response"
      and packet.requestId == requestId then
      return packet
    end
  end

  return {
    ok = false,
    error = "Player tracker timeout",
  }
end

local function sendUnauthorized(username, permission, authResult)
  local reason = authResult and authResult.reason or "Access denied"
  local required = authResult and authResult.requiredClearance or "?"
  local current = authResult and authResult.clearance or 0

  stats.denied = stats.denied + 1

  sendFormattedChat({
    { text = "UNAUTHORIZED", color = "red", bold = true },
    { text = "\nUser: ", color = "gray" },
    { text = tostring(username or "unknown"), color = "yellow" },
    { text = "\nPermission: ", color = "gray" },
    { text = tostring(permission), color = "aqua" },
    { text = "\nClearance: ", color = "gray" },
    { text = "CL" .. tostring(current) .. " / CL" .. tostring(required), color = "red" },
    { text = "\nReason: ", color = "gray" },
    { text = tostring(reason), color = "yellow" },
  })
end

local function requirePermission(username, permission)
  local allowed, authResult = nodeClient.authCheck(username, permission, 2.5)

  if not allowed then
    sendUnauthorized(username, permission, authResult)
    nodeClient.alert("Denied " .. tostring(username) .. " for " .. tostring(permission), "warning")
    return false
  end

  return true, authResult
end

local function sendWhereReply(packet)
  local player = packet.player
  local coords = packet.coords or {}
  local isOnline = packet.isOnline
  local matches = packet.matches

  local status = isOnline and "ONLINE" or "OFFLINE LAST KNOWN"
  local statusColor = isOnline and "green" or "gold"

  local parts = {
    { text = "[", color = "white" },
    { text = status, color = statusColor, bold = true },
    { text = "]\n", color = "white" },

    { text = "Target: ", color = "gray" },
    { text = tostring(player), color = "aqua", bold = true },

    { text = "\nDimension: ", color = "gray" },
    { text = formatDimension(coords.dimension), color = "yellow" },

    { text = "\nPosition: ", color = "gray" },
    { text = "X:" .. formatCoord(coords.x), color = "red" },
    { text = " Y:" .. formatCoord(coords.y), color = "green" },
    { text = " Z:" .. formatCoord(coords.z), color = "blue" },

    { text = "\nHealth: ", color = "gray" },
    { text = tostring(math.floor(tonumber(coords.health) or 0)), color = "red" },
  }

  if not isOnline then
    table.insert(parts, { text = "\nLast Seen: ", color = "gray" })
    table.insert(parts, { text = tostring(coords.lastSeen or "Unknown"), color = "light_purple" })
  end

  if isOnline and matches and matches > 1 then
    table.insert(parts, { text = "\nMatched: ", color = "gray" })
    table.insert(parts, { text = tostring(matches) .. " online names", color = "yellow" })
  end

  sendFormattedChat(parts)
end

local function getClearance(username)
  local _, auth = nodeClient.authCheck(username, "security.view", 2.5)
  return tonumber(auth and auth.clearance) or 0, auth
end

local function getNearbyPlayers()
  if not playerDetector or type(playerDetector.getPlayersInRange) ~= "function" then
    return {}
  end

  local ok, players = pcall(playerDetector.getPlayersInRange, chatRadius)

  if not ok or type(players) ~= "table" then
    return {}
  end

  local result = {}

  for _, entry in pairs(players) do
    if type(entry) == "string" then
      table.insert(result, entry)
    elseif type(entry) == "table" then
      local name = entry.name or entry.username or entry.player or entry.displayName
      if name then
        table.insert(result, name)
      end
    end
  end

  return result
end

local function buildWhoisParts(targetName, shownClearance, auth)
  local known = (tonumber(auth and auth.clearance) or 0) > 0

  local parts = {
    { text = "WHOIS", color = "aqua", bold = true },

    { text = "\nUser: ", color = "gray" },
    { text = tostring(auth and auth.user or targetName), color = "yellow" },

    { text = "\nClearance: ", color = "gray" },
    { text = "CL" .. tostring(shownClearance), color = shownClearance >= 4 and "gold" or "green", bold = shownClearance >= 4 },

    { text = "\nRole: ", color = "gray" },
    { text = tostring(auth and auth.role or "Unknown"), color = "light_purple" },

    { text = "\nStatus: ", color = "gray" },
    { text = tostring(auth and auth.status or (known and "Known" or "Unknown")), color = known and "green" or "red" },

    { text = "\nLast Seen: ", color = "gray" },
    { text = tostring(auth and auth.lastSeen or "Unknown"), color = "white" },

    { text = "\nPermissions: ", color = "gray" },
    { text = joinList(auth and auth.permissions), color = "aqua" },
  }

  if auth and auth.securityNote and tostring(auth.securityNote) ~= "" then
    table.insert(parts, { text = "\nSecurity Note: ", color = "red", bold = true })
    table.insert(parts, { text = tostring(auth.securityNote), color = "gold" })
  end

  return parts
end

local function sendWhoisPlain(targetName, shownClearance, auth)
  local user = tostring(auth and auth.user or targetName)
  local role = tostring(auth and auth.role or "Unknown")
  local status = tostring(auth and auth.status or "Unknown")
  local lastSeen = tostring(auth and auth.lastSeen or "Unknown")

  local message = string.format(
    "WHOIS | %s | CL%s | %s | %s | Last Seen: %s",
    user,
    tostring(shownClearance),
    role,
    status,
    lastSeen
  )

  -- Use plain radius chat for max compatibility.
  sendPlainChat(message)
end

local function getShownClearanceForViewer(viewerName, targetClearance)
  local viewerClearance = getClearance(viewerName)

  if targetClearance >= 5 and viewerClearance < 4 then
    return 4
  end

  return targetClearance
end

local function handleWhoisCommand(username, input)
  if not requirePermission(username, "auth.whois") then
    return
  end

  local target, resolveError, matches = resolveAuthUser(input)

  if not target then
    sendFormattedChat({
      { text = "Usage: ", color = "gray" },
      { text = "!whois <player>", color = "aqua" },
    })
    return
  end

  local _, targetAuth = nodeClient.authCheck(target, "security.view", 2.5)
  local targetClearance = tonumber(targetAuth and targetAuth.clearance) or 0
  local targetName = tostring(targetAuth and targetAuth.user or target)

  local shownClearance = getShownClearanceForViewer(username, targetClearance)
  sendFormattedChat(buildWhoisParts(targetName, shownClearance, targetAuth))
end

local function handleWhereCommand(username, input)
  if not requirePermission(username, "players.where") then
    return
  end

  local response = requestPlayerLookup(input)

  if not response.ok then
    sendFormattedChat({
      { text = "Lookup failed", color = "red", bold = true },
      { text = "\n" .. tostring(response.error), color = "gray" },
    })
    stats.errors = stats.errors + 1
    return
  end

  sendWhereReply(response)
end

local function handleSecurityCommand(username, input)
  if not requirePermission(username, "security.setLevel") then
    return
  end

  local level, reason = tostring(input or ""):match("^(%S+)%s*(.*)$")
  level = tostring(level or ""):upper()

  local validLevels = {
    GREEN = true,
    YELLOW = true,
    RED = true,
    BLACK = true,
  }

  if not validLevels[level] then
    sendFormattedChat({
      { text = "Usage: ", color = "gray" },
      { text = "!sec green/yellow/red/black", color = "aqua" },
    })
    return
  end

  nodeClient.setSecurityLevel(level, reason ~= "" and reason or ("set by " .. tostring(username)))
  nodeClient.alert("Security level requested: " .. level .. " by " .. tostring(username), level == "GREEN" and "info" or "warning")

  sendFormattedChat({
    { text = "Security level request sent: ", color = "gray" },
    { text = level, color = level == "GREEN" and "green" or (level == "YELLOW" and "yellow" or "red"), bold = true },
  })
end


local maintenanceProtocol = "subterra_maintenance"

local function requestMaintenance(packetType, responseType, data)
  local requestId = makeRequestId()
  local packet = data or {}

  packet.app = "subterra"
  packet.type = packetType
  packet.requestId = requestId

  rednet.broadcast(packet, maintenanceProtocol)

  local startedAt = os.clock()

  while os.clock() - startedAt < 2.5 do
    local _, response = rednet.receive(maintenanceProtocol, 2.5)

    if type(response) == "table"
      and response.app == "subterra"
      and response.type == responseType
      and response.requestId == requestId then
      return response
    end
  end

  return {
    ok = false,
    error = "Maintenance server timeout",
  }
end

local function handleMaintenanceStatusCommand(username)
  if not requirePermission(username, "maintenance.status") then return end

  local response = requestMaintenance("maintenance_status_request", "maintenance_status_response")

  if response.error then
    sendFormattedChat({
      { text = "Maintenance request failed", color = "red", bold = true },
      { text = "\n" .. tostring(response.error), color = "gray" },
    })
    return
  end

  sendFormattedChat({
    { text = "Maintenance Status", color = "aqua", bold = true },
    { text = "\nSecurity: ", color = "gray" },
    { text = tostring(response.securityLevel or "UNKNOWN"), color = "yellow", bold = true },
    { text = "\nNodes: ", color = "gray" },
    { text = tostring(response.online or 0) .. "/" .. tostring(response.total or 0) .. " online", color = "green" },
    { text = " | stale " .. tostring(response.stale or 0) .. " | offline " .. tostring(response.offline or 0), color = (response.offline or 0) > 0 and "red" or "gray" },
    { text = "\nPackets: ", color = "gray" },
    { text = tostring(response.packetCount or 0), color = "white" },
  })
end

local function handleMaintenanceNodesCommand(username)
  if not requirePermission(username, "maintenance.nodes") then return end

  local response = requestMaintenance("maintenance_nodes_request", "maintenance_nodes_response")

  local parts = {
    { text = "Nodes", color = "aqua", bold = true },
  }

  local nodes = response.nodes or {}
  local shown = 0

  for _, node in ipairs(nodes) do
    local status = tostring(node.status or "UNKNOWN")
    local color = status == "ONLINE" and "green" or (status == "STALE" and "gold" or "red")

    table.insert(parts, { text = "\n" .. tostring(node.name) .. ": ", color = "gray" })
    table.insert(parts, { text = status, color = color })

    shown = shown + 1
    if shown >= 8 then
      table.insert(parts, { text = "\n...more on monitor", color = "dark_gray" })
      break
    end
  end

  if #nodes == 0 then
    table.insert(parts, { text = "\nNo nodes found", color = "red" })
  end

  sendFormattedChat(parts)
end

local function handleMaintenanceOfflineCommand(username)
  if not requirePermission(username, "maintenance.nodes") then return end

  local response = requestMaintenance("maintenance_nodes_request", "maintenance_nodes_response", {
    filter = "offline",
  })

  local parts = {
    { text = "Offline/Stale Nodes", color = "aqua", bold = true },
  }

  local nodes = response.nodes or {}

  if #nodes == 0 then
    table.insert(parts, { text = "\nNone", color = "green" })
  else
    for _, node in ipairs(nodes) do
      local status = tostring(node.status or "UNKNOWN")
      table.insert(parts, { text = "\n" .. tostring(node.name) .. ": ", color = "gray" })
      table.insert(parts, { text = status, color = status == "STALE" and "gold" or "red" })
    end
  end

  sendFormattedChat(parts)
end

local function handleMaintenanceNodeCommand(username, input)
  if not requirePermission(username, "maintenance.nodes") then return end

  local response = requestMaintenance("maintenance_node_request", "maintenance_node_response", {
    query = input,
  })

  if not response.ok then
    sendFormattedChat({
      { text = "Node not found", color = "red", bold = true },
      { text = "\n" .. tostring(response.error or "Unknown error"), color = "gray" },
    })
    return
  end

  local node = response.node or {}
  local status = tostring(node.status or "UNKNOWN")

  sendFormattedChat({
    { text = "Node Details", color = "aqua", bold = true },
    { text = "\nName: ", color = "gray" },
    { text = tostring(node.name), color = "yellow" },
    { text = "\nStatus: ", color = "gray" },
    { text = status, color = status == "ONLINE" and "green" or (status == "STALE" and "gold" or "red"), bold = true },
    { text = "\nAge: ", color = "gray" },
    { text = tostring(node.age or "?") .. "s", color = "white" },
    { text = "\nRole: ", color = "gray" },
    { text = tostring(node.role or "unknown"), color = "light_purple" },
    { text = "\nLocation: ", color = "gray" },
    { text = tostring(node.location or "unknown"), color = "white" },
    { text = "\nServices: ", color = "gray" },
    { text = joinList(node.services), color = "aqua" },
  })
end

local function handleMaintenanceServicesCommand(username)
  if not requirePermission(username, "maintenance.services") then return end

  local response = requestMaintenance("maintenance_services_request", "maintenance_services_response")

  local parts = {
    { text = "Services", color = "aqua", bold = true },
  }

  local shown = 0

  for _, node in ipairs(response.nodes or {}) do
    table.insert(parts, { text = "\n" .. tostring(node.name) .. ": ", color = "gray" })
    table.insert(parts, { text = joinList(node.services), color = "white" })

    shown = shown + 1
    if shown >= 5 then
      table.insert(parts, { text = "\n...more on monitor", color = "dark_gray" })
      break
    end
  end

  sendFormattedChat(parts)
end


local function parseAddUserArgs(input)
  input = tostring(input or "")

  local name, role, clearance, status, note = input:match('^%s*"([^"]+)"%s+"([^"]+)"%s+(%S+)%s+(%S+)%s*(.-)%s*$')

  if not name then
    return nil, 'Usage: !adduser "Name" "Role" CL0-CL5 status [security note]'
  end

  return {
    name = name,
    role = role,
    clearance = clearance,
    status = status,
    securityNote = note or "",
  }
end

local function authManage(actor, action, target)
  local requestId = makeRequestId()

  rednet.broadcast({
    app = "subterra",
    type = "auth_manage",
    requestId = requestId,
    data = {
      action = action,
      actor = actor,
      target = target,
      requestId = requestId,
    },
  }, "subterra_auth")

  local startedAt = os.clock()

  while os.clock() - startedAt < 2.5 do
    local _, response = rednet.receive("subterra_auth", 2.5)

    if type(response) == "table"
      and response.app == "subterra"
      and response.type == "auth_manage_response"
      and response.requestId == requestId then
      return response
    end
  end

  return {
    ok = false,
    reason = "Auth server timeout",
  }
end

local function handleAddUserCommand(username, input)
  if not requirePermission(username, "auth.manage") then return end

  local target, parseError = parseAddUserArgs(input)

  if not target then
    sendFormattedChat({
      { text = parseError, color = "red" },
    })
    return
  end

  local response = authManage(username, "add", target)

  sendFormattedChat({
    { text = response.ok and "User saved" or "Add user failed", color = response.ok and "green" or "red", bold = true },
    { text = "\n" .. tostring(response.reason or ""), color = "gray" },
  })
end

local function handleRemoveUserCommand(username, input)
  if not requirePermission(username, "auth.manage") then return end

  local name = tostring(input or ""):match("^%s*(%S+)%s*$")

  if not name or name == "" then
    sendFormattedChat({
      { text = "Usage: !removeuser Name", color = "red" },
    })
    return
  end

  local response = authManage(username, "remove", {
    name = name,
  })

  sendFormattedChat({
    { text = response.ok and "User removed" or "Remove user failed", color = response.ok and "green" or "red", bold = true },
    { text = "\n" .. tostring(response.reason or ""), color = "gray" },
  })
end


local function parsePermissionArgs(input)
  input = tostring(input or "")

  local name, permission = input:match('^%s*"([^"]+)"%s+(%S+)%s*$')

  if not name then
    return nil, nil, 'Usage: !addperm "Name" permission.name'
  end

  return name, permission
end

local function handleAddPermissionCommand(username, input)
  if not requirePermission(username, "auth.manage") then return end

  local name, permission, parseError = parsePermissionArgs(input)

  if not name then
    sendFormattedChat({
      { text = parseError, color = "red" },
    })
    return
  end

  local response = authManage(username, "addperm", {
    name = name,
    permission = permission,
  })

  sendFormattedChat({
    { text = response.ok and "Permission added" or "Add permission failed", color = response.ok and "green" or "red", bold = true },
    { text = "\n" .. tostring(response.reason or ""), color = "gray" },
  })
end

local function handleRemovePermissionCommand(username, input)
  if not requirePermission(username, "auth.manage") then return end

  local name, permission, parseError = parsePermissionArgs(input)

  if not name then
    sendFormattedChat({
      { text = parseError:gsub("!addperm", "!removeperm"), color = "red" },
    })
    return
  end

  local response = authManage(username, "removeperm", {
    name = name,
    permission = permission,
  })

  sendFormattedChat({
    { text = response.ok and "Permission removed" or "Remove permission failed", color = response.ok and "green" or "red", bold = true },
    { text = "\n" .. tostring(response.reason or ""), color = "gray" },
  })
end


local personnelProtocol = "subterra_personnel"

local function requestPersonnel(packetType, responseType, data)
  local requestId = makeRequestId()
  local packet = data or {}

  packet.app = "subterra"
  packet.type = packetType
  packet.requestId = requestId

  rednet.broadcast(packet, personnelProtocol)

  local startedAt = os.clock()

  while os.clock() - startedAt < 3 do
    local _, response = rednet.receive(personnelProtocol, 3)

    if type(response) == "table"
      and response.app == "subterra"
      and response.type == responseType
      and response.requestId == requestId then
      return response
    end
  end

  return {
    ok = false,
    error = "Personnel server timeout",
    users = {},
  }
end

local function sendPersonnelList(users, title, total)
  local parts = {
    { text = title or "Personnel", color = "aqua", bold = true },
  }

  local shown = 0

  for _, user in ipairs(users or {}) do
    local color = "white"
    local status = tostring(user.status or ""):lower()
    local role = tostring(user.role or ""):lower()
    local clearance = tonumber(user.clearance) or 0

    if status == "fired" then color = "red"
    elseif role:find("visitor", 1, true) then color = "yellow"
    elseif clearance == 0 then color = "gold"
    elseif clearance >= 5 then color = "light_purple"
    elseif clearance >= 4 then color = "green" end

    table.insert(parts, { text = "\n" .. tostring(user.clearanceLabel or ("CL" .. tostring(user.clearance or 0))) .. " ", color = color, bold = true })
    table.insert(parts, { text = tostring(user.name or "Unknown"), color = color })
    table.insert(parts, { text = " | " .. tostring(user.role or "Unknown"), color = "gray" })
    table.insert(parts, { text = " | " .. tostring(user.status or "Unknown"), color = color })

    shown = shown + 1

    if shown >= 8 then
      table.insert(parts, { text = "\n...showing 8/" .. tostring(total or #users), color = "dark_gray" })
      break
    end
  end

  if shown == 0 then
    table.insert(parts, { text = "\nNo users found", color = "red" })
  end

  sendFormattedChat(parts)
end

local function handlePersonnelCommand(username, input)
  if not requirePermission(username, "auth.view") then return end

  local filter, query = tostring(input or ""):match("^(%S*)%s*(.-)$")
  filter = filter ~= "" and filter or "all"

  local response = requestPersonnel("personnel_list_request", "personnel_list_response", {
    filter = filter,
    query = query,
  })

  if not response.ok then
    sendFormattedChat({
      { text = "Personnel request failed", color = "red", bold = true },
      { text = "\n" .. tostring(response.error or "Unknown error"), color = "gray" },
    })
    return
  end

  sendPersonnelList(response.users or {}, "Personnel: " .. filter, response.total)
end

local function handlePersonnelRefreshCommand(username)
  if not requirePermission(username, "auth.view") then return end

  local response = requestPersonnel("personnel_refresh_request", "personnel_refresh_response")

  sendFormattedChat({
    { text = response.ok and "Personnel refreshed" or "Personnel refresh failed", color = response.ok and "green" or "red", bold = true },
    { text = "\nUsers: " .. tostring(response.total or 0), color = "gray" },
    { text = response.error and ("\n" .. tostring(response.error)) or "", color = "red" },
  })
end


local function handleHelpCommand()
  sendFormattedChat({
    { text = "SubTerra Commands", color = "aqua", bold = true },

    { text = "\nPlayer: ", color = "yellow", bold = true },
    { text = "!where <name>, !whois <name>", color = "gray" },

    { text = "\nSecurity: ", color = "yellow", bold = true },
    { text = "!sec <green/yellow/red/black>", color = "gray" },

    { text = "\nAuth: ", color = "yellow", bold = true },
    { text = "!adduser \"Name\" \"Role\" CL0-CL5 status [note]", color = "gray" },
    { text = "\n      !removeuser <name>, !addperm \"Name\" permission, !removeperm \"Name\" permission", color = "gray" },

    { text = "\nMaintenance: ", color = "yellow", bold = true },
    { text = "!status, !nodes, !offline, !node <name>, !services", color = "gray" },

    { text = "\nPersonnel: ", color = "yellow", bold = true },
    { text = "!personnel, !personnel cl4/fired/visitors, !personnel search <name>, !personnelrefresh", color = "gray" },
  })
end

local function handleChatCommand(username, message)
  local command, args = tostring(message or ""):match("^!(%S+)%s*(.*)$")
  if not command then return end

  command = command:lower()
  stats.commands = stats.commands + 1
  stats.lastUser = tostring(username or "unknown")
  stats.lastCommand = command
  addLog(tostring(username) .. " ran !" .. command)

  if command == "where" then
    handleWhereCommand(username, args)
  elseif command == "whois" then
    handleWhoisCommand(username, args)
  elseif command == "sec" or command == "security" then
    handleSecurityCommand(username, args)
  elseif command == "adduser" then
    handleAddUserCommand(username, args)
  elseif command == "removeuser" then
    handleRemoveUserCommand(username, args)
  elseif command == "addperm" then
    handleAddPermissionCommand(username, args)
  elseif command == "removeperm" then
    handleRemovePermissionCommand(username, args)
  elseif command == "status" or command == "maint" then
    handleMaintenanceStatusCommand(username)
  elseif command == "nodes" then
    handleMaintenanceNodesCommand(username)
  elseif command == "offline" then
    handleMaintenanceOfflineCommand(username)
  elseif command == "node" then
    handleMaintenanceNodeCommand(username, args)
  elseif command == "services" then
    handleMaintenanceServicesCommand(username)
  elseif command == "personnel" then
    handlePersonnelCommand(username, args)
  elseif command == "personnelrefresh" then
    handlePersonnelRefreshCommand(username)
  elseif command == "help" then
    handleHelpCommand()
  end

  redraw()
end

local function chatLoop()
  while true do
    local _, username, message = os.pullEvent("chat")
    handleChatCommand(username, message)
  end
end

local function monitorLoop()
  while true do
    redraw()
    sleep(1)
  end
end

local function safeSecurityListenLoop()
  nodeClient.securityListenLoop(function()
    redraw()
  end)
end

addLog("Command server online")
redraw()
parallel.waitForAll(chatLoop, monitorLoop, nodeClient.heartbeatLoop, safeSecurityListenLoop)
