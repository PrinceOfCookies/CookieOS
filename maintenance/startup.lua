-- startup.lua
-- SubTerra Maintenance Server
-- DATA ONLY: collects node status and answers Command Server requests.

local nodeClient = require("subterra_node_client")

nodeClient.init({
  modemSide = "back",
  protocol = "subterra_core",
  authProtocol = "subterra_auth",
  heartbeatSeconds = 5,
  node = "maintenance_server",
  role = "maintenance_data",
  location = "Server Room",
  services = {
    "maintenance.monitor",
    "maintenance.status_data",
    "maintenance.node_data",
    "maintenance.services_data",
  }
})

local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found") end

monitor.setTextScale(0.5)

local coreProtocol = "subterra_core"
local maintenanceProtocol = "subterra_maintenance"

local nodes = {}
local packetCount = 0
local packetsPerMinute = 0
local securityLevel = "GREEN"

local staleAfter = 15
local deadAfter = 45

local ppmCounter = 0
local ppmTimer = os.clock()

local function trimText(text, maxWidth)
  text = tostring(text or "")
  maxWidth = tonumber(maxWidth) or #text

  if #text <= maxWidth then return text end
  if maxWidth <= 3 then return text:sub(1, maxWidth) end

  return text:sub(1, maxWidth - 3) .. "..."
end

local function drawLine(y, text, color, bg)
  local width, height = monitor.getSize()
  if y < 1 or y > height then return end

  monitor.setCursorPos(1, y)
  monitor.setBackgroundColor(bg or colors.black)
  monitor.setTextColor(color or colors.white)
  monitor.clearLine()
  monitor.write(trimText(text, width))
end

local function drawCentered(y, text, color, bg)
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

local function getNodeStatus(node)
  local age = os.clock() - (node.lastSeenClock or 0)

  if age > deadAfter then return "OFFLINE", colors.red end
  if age > staleAfter then return "STALE", colors.orange end

  return "ONLINE", colors.lime
end

local function sortedNodes()
  local result = {}

  for name, node in pairs(nodes) do
    table.insert(result, { name = name, node = node })
  end

  table.sort(result, function(a, b)
    return a.name < b.name
  end)

  return result
end

local function getSummaryCounts()
  local total, online, stale, offline = 0, 0, 0, 0

  for _, entry in ipairs(sortedNodes()) do
    total = total + 1
    local status = getNodeStatus(entry.node)

    if status == "ONLINE" then online = online + 1
    elseif status == "STALE" then stale = stale + 1
    elseif status == "OFFLINE" then offline = offline + 1 end
  end

  return total, online, stale, offline
end

local function findNode(input)
  input = tostring(input or ""):lower()
  if input == "" then return nil end

  local bestName, bestNode, bestScore = nil, nil, nil

  for name, node in pairs(nodes) do
    local lowerName = name:lower()
    local startIndex = lowerName:find(input, 1, true)

    if startIndex then
      local score = startIndex + math.abs(#lowerName - #input)

      if not bestScore or score < bestScore then
        bestName, bestNode, bestScore = name, node, score
      end
    end
  end

  return bestName, bestNode
end

local function updatePPM()
  ppmCounter = ppmCounter + 1
  local elapsed = os.clock() - ppmTimer

  if elapsed >= 60 then
    packetsPerMinute = ppmCounter
    ppmCounter = 0
    ppmTimer = os.clock()
  end
end

local function makePublicNode(name, node)
  local status = getNodeStatus(node)
  local age = math.floor(os.clock() - (node.lastSeenClock or 0))

  return {
    name = name,
    id = node.id,
    role = node.role,
    location = node.location,
    services = node.services or {},
    status = status,
    age = age,
    securityLevel = node.securityLevel,
    rawStatus = node.status,
  }
end

local function getPublicNodes(filter)
  local result = {}

  for _, entry in ipairs(sortedNodes()) do
    local public = makePublicNode(entry.name, entry.node)

    if filter == "offline" then
      if public.status ~= "ONLINE" then table.insert(result, public) end
    else
      table.insert(result, public)
    end
  end

  return result
end

local function redraw()
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()

  monitor.setCursorPos(1, 1)
  monitor.setBackgroundColor(colors.red)
  monitor.clearLine()
  drawCentered(1, "SUBTERRA MAINTENANCE SERVER", colors.white, colors.red)

  drawCentered(3, "Data Service / Network Monitor", colors.lime)
  drawLine(5, "Security Level: " .. securityLevel, colors.yellow)
  drawLine(6, "Packets Seen: " .. packetCount .. " | Packets/min: " .. packetsPerMinute, colors.lightGray)

  local total, online, stale, offline = getSummaryCounts()
  drawLine(7, "Nodes: " .. online .. "/" .. total .. " online | stale " .. stale .. " | off " .. offline, colors.lightBlue)

  drawLine(9, "Nodes", colors.yellow)

  local y = 10
  local _, height = monitor.getSize()

  for _, entry in ipairs(sortedNodes()) do
    local node = entry.node
    local status, color = getNodeStatus(node)
    local age = math.floor(os.clock() - (node.lastSeenClock or 0))

    drawLine(y, string.format("%-18s %-8s %2ss", trimText(entry.name, 18), status, tostring(age)), color)
    y = y + 1

    if y <= height then
      drawLine(y, "  " .. tostring(node.role or "?") .. " | " .. tostring(node.location or "unknown"), colors.gray)
      y = y + 1
    end

    if y > height - 2 then break end
  end
end

local function handleCorePacket(senderId, packet)
  if type(packet) ~= "table" or packet.app ~= "subterra" then return end

  packetCount = packetCount + 1
  updatePPM()

  if packet.type == "heartbeat" then
    local nodeName = tostring(packet.node or ("computer_" .. tostring(senderId)))

    nodes[nodeName] = {
      id = senderId,
      role = packet.role or "unknown",
      location = packet.location or "unknown",
      services = packet.services or {},
      lastSeenClock = os.clock(),
      lastSeenTime = os.time(),
      securityLevel = packet.securityLevel,
      status = packet.status,
    }
  elseif packet.type == "security_state" then
    securityLevel = tostring(packet.level or "GREEN")
  end
end

local function handleMaintenanceRequest(senderId, packet)
  if type(packet) ~= "table" or packet.app ~= "subterra" then return end

  local requestId = packet.requestId

  if packet.type == "maintenance_status_request" then
    local total, online, stale, offline = getSummaryCounts()

    rednet.send(senderId, {
      app = "subterra",
      type = "maintenance_status_response",
      requestId = requestId,
      securityLevel = securityLevel,
      packetCount = packetCount,
      packetsPerMinute = packetsPerMinute,
      total = total,
      online = online,
      stale = stale,
      offline = offline,
    }, maintenanceProtocol)
  elseif packet.type == "maintenance_nodes_request" then
    rednet.send(senderId, {
      app = "subterra",
      type = "maintenance_nodes_response",
      requestId = requestId,
      nodes = getPublicNodes(packet.filter),
    }, maintenanceProtocol)
  elseif packet.type == "maintenance_node_request" then
    local name, node = findNode(packet.query)

    rednet.send(senderId, {
      app = "subterra",
      type = "maintenance_node_response",
      requestId = requestId,
      ok = node ~= nil,
      node = node and makePublicNode(name, node) or nil,
      error = node and nil or ("Node not found: " .. tostring(packet.query or "")),
    }, maintenanceProtocol)
  elseif packet.type == "maintenance_services_request" then
    rednet.send(senderId, {
      app = "subterra",
      type = "maintenance_services_response",
      requestId = requestId,
      nodes = getPublicNodes(),
    }, maintenanceProtocol)
  end
end

local function coreReceiveLoop()
  while true do
    local senderId, packet = rednet.receive(coreProtocol, 1)
    if senderId then handleCorePacket(senderId, packet) end
  end
end

local function maintenanceReceiveLoop()
  while true do
    local senderId, packet = rednet.receive(maintenanceProtocol, 1)
    if senderId then handleMaintenanceRequest(senderId, packet) end
  end
end

local function redrawLoop()
  while true do
    redraw()
    sleep(1)
  end
end

parallel.waitForAll(coreReceiveLoop, maintenanceReceiveLoop, redrawLoop, nodeClient.heartbeatLoop)
