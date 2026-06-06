-- startup.lua
-- SubTerra Core Server
-- Live dashboard for heartbeats, alerts, and security state.

local modemSide = "back"
local protocol = "subterra_core"

local staleAfter = 15
local deadAfter = 45

local monitor = peripheral.find("monitor")
if monitor then monitor.setTextScale(0.5) end

if peripheral.getType(modemSide) ~= "modem" then
  error("No modem on " .. modemSide)
end

rednet.open(modemSide)

local nodes = {}
local alerts = {}
local securityLevel = "GREEN"

local securityColors = {
  GREEN = colors.lime,
  YELLOW = colors.yellow,
  RED = colors.red,
  BLACK = colors.purple,
}

local validSecurityLevels = {
  GREEN = true,
  YELLOW = true,
  RED = true,
  BLACK = true,
}

local function trimText(text, maxWidth)
  text = tostring(text or "")
  maxWidth = tonumber(maxWidth) or #text

  if #text <= maxWidth then return text end
  if maxWidth <= 3 then return text:sub(1, maxWidth) end

  return text:sub(1, maxWidth - 3) .. "..."
end

local function addAlert(source, message, level)
  table.insert(alerts, 1, {
    time = textutils.formatTime(os.time(), true),
    source = tostring(source or "?"),
    message = tostring(message or ""),
    level = tostring(level or "info"),
  })

  while #alerts > 10 do
    table.remove(alerts)
  end
end

local function broadcastSecurityState(reason)
  rednet.broadcast({
    app = "subterra",
    type = "security_state",
    level = securityLevel,
    reason = reason or "update",
    source = "core",
    time = os.time(),
  }, protocol)
end

local function setSecurityLevel(level, source, reason)
  level = tostring(level or ""):upper()

  if not validSecurityLevels[level] then
    addAlert(source or "core", "Invalid security level: " .. tostring(level), "warning")
    return false
  end

  if securityLevel ~= level then
    securityLevel = level
    addAlert(source or "core", "Security level changed to " .. level .. (reason and (" | " .. reason) or ""), level == "GREEN" and "info" or "critical")
  end

  broadcastSecurityState(reason or ("set by " .. tostring(source or "core")))
  return true
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

local function getNodeStatus(node)
  local age = os.clock() - (node.lastSeenClock or 0)

  if age > deadAfter then return "OFFLINE", colors.red end
  if age > staleAfter then return "STALE", colors.orange end

  return "ONLINE", colors.lime
end

local function sortedNodeNames()
  local names = {}

  for name in pairs(nodes) do
    table.insert(names, name)
  end

  table.sort(names)
  return names
end

local function redraw()
  if not monitor then return end

  local _, height = monitor.getSize()
  local levelColor = securityColors[securityLevel] or colors.white

  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()

  monitor.setCursorPos(1, 1)
  monitor.setBackgroundColor(levelColor)
  monitor.clearLine()
  drawCentered(1, "SUBTERRA CORE | " .. securityLevel .. " | " .. textutils.formatTime(os.time(), true), colors.black, levelColor)

  drawCentered(3, "Server Room Node Monitor", colors.lime)
  drawLine(5, "Protocol: " .. protocol .. " | Nodes: " .. tostring(#sortedNodeNames()), colors.lightGray)

  local y = 7
  drawLine(y, "Nodes", colors.yellow)
  y = y + 1

  for _, name in ipairs(sortedNodeNames()) do
    local node = nodes[name]
    local status, color = getNodeStatus(node)
    local age = math.floor(os.clock() - (node.lastSeenClock or 0))

    drawLine(y, string.format("%-18s %-7s %-10s %ss", trimText(name, 18), status, trimText(node.role or "?", 10), age), color)
    y = y + 1

    if y <= height then
      drawLine(y, "  " .. tostring(node.location or "unknown"), colors.gray)
      y = y + 1
    end

    if y > height - 9 then break end
  end

  if y <= height then
    y = y + 1
    drawLine(y, "Alerts / Events", colors.yellow)
    y = y + 1

    for _, alert in ipairs(alerts) do
      if y > height then break end

      local color = colors.lightGray
      if alert.level == "warning" then color = colors.orange end
      if alert.level == "error" or alert.level == "critical" or alert.level == "RED" or alert.level == "BLACK" then color = colors.red end
      if alert.level == "YELLOW" then color = colors.yellow end

      drawLine(y, alert.time .. " " .. alert.source .. ": " .. alert.message, color)
      y = y + 1
    end
  end
end

local function handlePacket(senderId, packet)
  if type(packet) ~= "table" or packet.app ~= "subterra" then return end

  if packet.type == "heartbeat" then
    local nodeName = tostring(packet.node or ("computer_" .. tostring(senderId)))

    nodes[nodeName] = {
      id = senderId,
      node = nodeName,
      role = packet.role or "unknown",
      location = packet.location or "unknown",
      status = packet.status or "online",
      services = packet.services or {},
      lastSeenClock = os.clock(),
      lastSeenTime = os.time(),
    }
  elseif packet.type == "alert" then
    addAlert(packet.node or senderId, packet.message, packet.level)
  elseif packet.type == "security_level" then
    setSecurityLevel(packet.level, packet.node or senderId, packet.reason or packet.message)
  elseif packet.type == "request_security_state" then
    broadcastSecurityState("requested")
  end
end

local function receiveLoop()
  while true do
    local senderId, packet = rednet.receive(protocol, 1)

    if senderId then
      handlePacket(senderId, packet)
      redraw()
    end
  end
end

local function drawLoop()
  while true do
    redraw()
    sleep(1)
  end
end

addAlert("core", "Core online", "info")
broadcastSecurityState("core startup")
parallel.waitForAll(receiveLoop, drawLoop)
