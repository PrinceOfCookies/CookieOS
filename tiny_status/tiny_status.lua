-- tiny_status.lua
-- SubTerra Tiny Node Status Monitor
-- Draws ONLY to the monitor on top.

local nodeClient = require("subterra_node_client")

local monitorSide = "top"
local modemSide = "back"

local nodeName = "CHANGE_ME"
local nodeRole = "status"
local nodeLocation = "S1C2R1"

local coreProtocol = "subterra_core"
local authProtocol = "subterra_auth"

local monitor = peripheral.wrap(monitorSide)
if not monitor then error("No monitor on " .. monitorSide) end
if peripheral.getType(monitorSide) ~= "monitor" then error("Peripheral on " .. monitorSide .. " is not a monitor") end

monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()

nodeClient.init({
  modemSide = modemSide,
  protocol = coreProtocol,
  authProtocol = authProtocol,
  heartbeatSeconds = 5,
  node = nodeName .. "_tiny_status",
  role = nodeRole,
  location = nodeLocation,
  services = {
    "status.tiny",
  }
})

local lastCorePacketAt = nil
local packetCount = 0
local blink = false
local currentSecurityLevel = "GREEN"

local statusColors = {
  GREEN = colors.lime,
  YELLOW = colors.yellow,
  RED = colors.red,
  BLACK = colors.purple,
}

local function trimText(text, maxWidth)
  text = tostring(text or "")

  if #text <= maxWidth then return text end
  if maxWidth <= 3 then return text:sub(1, maxWidth) end

  return text:sub(1, maxWidth - 3) .. "..."
end

local function writeAt(x, y, text, color, bg)
  local width, height = monitor.getSize()

  if y < 1 or y > height then return end

  monitor.setCursorPos(math.max(1, x), y)
  monitor.setTextColor(color or colors.white)
  monitor.setBackgroundColor(bg or colors.black)
  monitor.write(trimText(text, width - x + 1))
end

local function getConnectionStatus()
  if not lastCorePacketAt then
    return "WAITING", colors.orange
  end

  local age = os.clock() - lastCorePacketAt

  if age <= 10 then return "ONLINE", colors.lime end
  if age <= 25 then return "STALE", colors.orange end

  return "OFFLINE", colors.red
end

local function redraw()
  local width = monitor.getSize()
  local connText, connColor = getConnectionStatus()
  local secColor = statusColors[currentSecurityLevel] or colors.white

  blink = not blink

  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()

  writeAt(1, 1, blink and "*" or "o", connColor)
  writeAt(3, 1, trimText(nodeName, width - 2), colors.aqua)

  writeAt(1, 3, "NET:", colors.gray)
  writeAt(6, 3, connText, connColor)

  writeAt(1, 4, "SEC:", colors.gray)
  writeAt(6, 4, currentSecurityLevel, secColor)

  writeAt(1, 5, "ROLE:", colors.gray)
  writeAt(7, 5, nodeRole, colors.lightGray)

  writeAt(1, 6, "LOC:", colors.gray)
  writeAt(6, 6, nodeLocation, colors.lightBlue)

  writeAt(1, 7, "PKT:", colors.gray)
  writeAt(6, 7, tostring(packetCount), colors.white)

  writeAt(1, 8, "AGE:", colors.gray)

  if lastCorePacketAt then
    writeAt(6, 8, tostring(math.floor(os.clock() - lastCorePacketAt)) .. "s", colors.white)
  else
    writeAt(6, 8, "none", colors.red)
  end
end

local function receiveLoop()
  if peripheral.getType(modemSide) ~= "modem" then
    while true do sleep(1) end
  end

  if not rednet.isOpen(modemSide) then
    rednet.open(modemSide)
  end

  while true do
    local _, packet = rednet.receive(coreProtocol, 1)

    if type(packet) == "table" and packet.app == "subterra" then
      packetCount = packetCount + 1
      lastCorePacketAt = os.clock()

      if packet.type == "security_state" then
        currentSecurityLevel = tostring(packet.level or currentSecurityLevel):upper()
      end
    end
  end
end

local function drawLoop()
  while true do
    redraw()
    sleep(0.5)
  end
end

parallel.waitForAll(receiveLoop, drawLoop, nodeClient.heartbeatLoop)
