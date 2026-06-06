-- startup.lua
-- SubTerra Facility Map Server
-- Fake 3D/isometric floor-aware player map.
--
-- Dot colors:
-- Green  = user exists in Auth and is not Visitor and not CL0
-- Yellow = user exists in Auth and role is Visitor
-- Orange = user exists in Auth, CL0, and not Visitor
-- Red    = user is not in Auth

local nodeClient = require("subterra_node_client")

nodeClient.init({
  modemSide = "back",
  protocol = "subterra_core",
  authProtocol = "subterra_auth",
  heartbeatSeconds = 5,
  node = "facility_map",
  role = "mapping",
  location = "Server Room",
  services = {
    "map.facility",
    "map.players",
    "map.security",
  }
})

local playerDetector = peripheral.find("player_detector")
local monitor = peripheral.find("monitor")

if not playerDetector then error("No player detector found") end
if not monitor then error("No monitor found") end

monitor.setTextScale(0.5)

local realMonitor = monitor
local monitorWidth, monitorHeight = realMonitor.getSize()
monitor = window.create(realMonitor, 1, 1, monitorWidth, monitorHeight, false)

local facility = {
  name = "SubTerra",
  site = "Site 6",

  -- Floor 1 was expanded by +1 length/width from your given corners.
  bounds = {
    minX = -323345,
    maxX = -323312,

    minZ = -1041,
    maxZ = -1008,
  },

  -- Each floor was expanded by +2 height:
  -- Original Floor 1: 31-38
  -- New Floor 1:      30-39
  -- 3 block separation between floors.
  floors = {
    { name = "F1", minY = 30,  maxY = 39,  color = colors.lime },
    { name = "F2", minY = 17,  maxY = 26,  color = colors.cyan },
    { name = "F3", minY = 4,   maxY = 13,  color = colors.lightBlue },
    { name = "F4", minY = -9,  maxY = 0,   color = colors.yellow },
    { name = "F5", minY = -22, maxY = -13, color = colors.orange },
    { name = "F6", minY = -35, maxY = -26, color = colors.pink },

    -- If your detector used to call your floor F7 but you know it is F8,
    -- this label correction makes that Y band display as F8.
    { name = "F7", minY = -38, maxY = -36, color = colors.lightGray },
    { name = "F8", minY = -48, maxY = -39, color = colors.purple },
    { name = "F9", minY = -61, maxY = -52, color = colors.gray },
  },
}

local refreshSeconds = 0.25
local playerRange = 256
local authCacheSeconds = 8
local alertCooldown = 20

local authCache = {}
local displayPositions = {}
local lastStaticDrawAt = 0
local staticRedrawSeconds = 5

local lastUnknownAlertAt = 0
local lastAuthErrorAt = 0

local bgColor = colors.black
local gridColor = colors.gray
local wallColor = colors.lightGray
local textColor = colors.white

local dotColors = {
  recognized = colors.lime,
  visitor = colors.yellow,
  cl0 = colors.orange,
  unknown = colors.red,
}

local function clamp(value, minValue, maxValue)
  value = tonumber(value) or 0

  if value < minValue then return minValue end
  if value > maxValue then return maxValue end

  return value
end

local function lerp(a, b, t)
  return a + ((b - a) * t)
end

local function normalize(value, minValue, maxValue)
  if maxValue == minValue then
    return 0
  end

  return (value - minValue) / (maxValue - minValue)
end

local function trimText(text, maxWidth)
  text = tostring(text or "")

  if #text <= maxWidth then
    return text
  end

  if maxWidth <= 3 then
    return text:sub(1, maxWidth)
  end

  return text:sub(1, maxWidth - 3) .. "..."
end

local function writeAt(x, y, text, color, bg)
  local width, height = monitor.getSize()

  x = math.floor(x)
  y = math.floor(y)

  if x < 1 or y < 1 or x > width or y > height then
    return
  end

  monitor.setCursorPos(x, y)
  monitor.setTextColor(color or textColor)
  monitor.setBackgroundColor(bg or bgColor)
  monitor.write(trimText(text, width - x + 1))
end

local function writeCentered(y, text, color, bg)
  local width = monitor.getSize()
  text = trimText(text, width)

  local x = math.floor((width - #text) / 2) + 1
  writeAt(x, y, text, color, bg)
end

local function clearScreen()
  monitor.setBackgroundColor(bgColor)
  monitor.setTextColor(textColor)
  monitor.clear()
end

local function getPlayerList()
  if type(playerDetector.getOnlinePlayers) == "function" then
    local ok, players = pcall(playerDetector.getOnlinePlayers)

    if ok and type(players) == "table" then
      return players
    end
  end

  if type(playerDetector.getPlayersInRange) == "function" then
    local ok, players = pcall(playerDetector.getPlayersInRange, playerRange)

    if ok and type(players) == "table" then
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
  end

  return {}
end

local function getPlayerPos(player)
  if type(playerDetector.getPlayerPos) ~= "function" then
    return nil
  end

  local ok, pos = pcall(playerDetector.getPlayerPos, player)

  if ok and type(pos) == "table" then
    return pos
  end

  return nil
end

local function getFloorForY(y)
  y = tonumber(y)

  if not y then
    return nil
  end

  for index, floor in ipairs(facility.floors) do
    if y >= floor.minY and y <= floor.maxY then
      return floor, index
    end
  end

  return nil
end

local function getAuthInfo(player)
  local now = os.clock()
  local cached = authCache[player]

  if cached and now - cached.cachedAt <= authCacheSeconds then
    return cached
  end

  local allowed, auth = nodeClient.authCheck(player, "security.view", 2.5)

  local result = {
    exists = false,
    clearance = 0,
    role = "Unknown",
    status = "Unknown",
    user = player,
    cachedAt = now,
  }

  if type(auth) == "table" then
    local reason = tostring(auth.reason or "")

    -- Unknown users come back denied with reason "Unknown user".
    if reason ~= "Unknown user" then
      result.exists = true
      result.clearance = tonumber(auth.clearance) or 0
      result.role = tostring(auth.role or "Unknown")
      result.status = tostring(auth.status or "Unknown")
      result.user = tostring(auth.user or player)
      result.securityNote = tostring(auth.securityNote or "")
    end
  else
    if now - lastAuthErrorAt > 10 then
      nodeClient.alert("Facility map auth lookup failed", "warning")
      lastAuthErrorAt = now
    end
  end

  authCache[player] = result
  return result
end

local function getPlayerDotStyle(player)
  local auth = getAuthInfo(player)
  local roleLower = tostring(auth.role or ""):lower()

  if not auth.exists then
    return "R", dotColors.unknown, "unknown", auth
  end

  if roleLower == "visitor" or roleLower:find("visitor", 1, true) then
    return "Y", dotColors.visitor, "visitor", auth
  end

  if tonumber(auth.clearance) == 0 then
    return "O", dotColors.cl0, "cl0", auth
  end

  return "G", dotColors.recognized, "recognized", auth
end

local function projectPosition(pos, floorIndex)
  local width, height = monitor.getSize()

  local mapLeft = 3
  local mapTop = 5
  local mapWidth = width - 6
  local mapHeight = height - 10

  local nx = normalize(pos.x, facility.bounds.minX, facility.bounds.maxX)
  local nz = normalize(pos.z, facility.bounds.minZ, facility.bounds.maxZ)

  nx = clamp(nx, 0, 1)
  nz = clamp(nz, 0, 1)

  local floorCount = math.max(1, #facility.floors)
  local floorBandHeight = math.max(2, math.floor(mapHeight / floorCount))

  local baseY = mapTop + ((floorIndex or 1) - 1) * floorBandHeight
  local floorHeight = math.max(1, floorBandHeight - 1)

  -- Fake angled 3D projection:
  -- X moves right.
  -- Z shifts diagonally right/down.
  -- Floor index stacks vertically downward.
  local screenX = mapLeft + (nx * mapWidth * 0.72) + (nz * mapWidth * 0.22)
  local screenY = baseY + (nz * floorHeight * 0.65)

  return screenX, screenY
end

local function smoothPosition(player, x, y)
  local old = displayPositions[player]

  if not old then
    displayPositions[player] = { x = x, y = y }
    return x, y
  end

  old.x = lerp(old.x, x, 0.45)
  old.y = lerp(old.y, y, 0.45)

  return old.x, old.y
end

local function drawLine(x1, y1, x2, y2, char, color)
  local dx = x2 - x1
  local dy = y2 - y1
  local steps = math.max(math.abs(dx), math.abs(dy))

  if steps <= 0 then
    writeAt(x1, y1, char, color)
    return
  end

  for i = 0, steps do
    local t = i / steps
    local x = x1 + dx * t
    local y = y1 + dy * t

    writeAt(x, y, char, color)
  end
end

local function drawFloorBand(floor, index)
  local width, height = monitor.getSize()

  local mapLeft = 3
  local mapTop = 5
  local mapWidth = width - 6
  local mapHeight = height - 10

  local floorCount = math.max(1, #facility.floors)
  local floorBandHeight = math.max(2, math.floor(mapHeight / floorCount))

  local y = mapTop + (index - 1) * floorBandHeight
  local left = mapLeft
  local right = mapLeft + math.floor(mapWidth * 0.88)
  local depthX = math.max(3, math.floor(mapWidth * 0.12))
  local depthY = math.max(1, math.floor(floorBandHeight * 0.45))
  local bottomY = y + math.max(1, floorBandHeight - 1)

  local color = floor.color or wallColor

  -- Isometric-ish floor slab.
  drawLine(left, y, right, y, "-", color)
  drawLine(left + depthX, bottomY, right + depthX, bottomY, "-", color)
  drawLine(left, y, left + depthX, bottomY, "/", color)
  drawLine(right, y, right + depthX, bottomY, "/", color)

  writeAt(1, y, floor.name, color)
end

local function drawFacilityFrame()
  for index, floor in ipairs(facility.floors) do
    drawFloorBand(floor, index)
  end
end

local function drawHeader(onlineCount, unknownCount, visitorCount, cl0Count)
  monitor.setCursorPos(1, 1)
  monitor.setBackgroundColor(colors.red)
  monitor.clearLine()

  writeCentered(1, facility.name .. " : " .. facility.site .. " MAP | " .. textutils.formatTime(os.time(), true), colors.white, colors.red)

  monitor.setBackgroundColor(bgColor)
  writeCentered(
    3,
    "Players " .. onlineCount .. " | Unknown " .. unknownCount .. " | Visitors " .. visitorCount .. " | CL0 " .. cl0Count,
    unknownCount > 0 and colors.red or colors.lime,
    bgColor
  )
end

local function drawLegend()
  local width, height = monitor.getSize()

  writeAt(2, height - 1, "G auth", colors.lime)
  writeAt(11, height - 1, "Y visitor", colors.yellow)
  writeAt(23, height - 1, "O CL0", colors.orange)
  writeAt(31, height - 1, "R unknown", colors.red)
  writeAt(width - 14, height - 1, "9 Floors", colors.gray)
end

local function drawPlayers()
  local players = getPlayerList()
  local onlineCount = #players
  local unknownCount = 0
  local visitorCount = 0
  local cl0Count = 0
  local activePlayers = {}

  for _, player in ipairs(players) do
    activePlayers[player] = true

    local pos = getPlayerPos(player)

    if pos then
      local floor, floorIndex = getFloorForY(pos.y)

      if floor then
        local marker, color, category, auth = getPlayerDotStyle(player)

        if category == "unknown" then unknownCount = unknownCount + 1 end
        if category == "visitor" then visitorCount = visitorCount + 1 end
        if category == "cl0" then cl0Count = cl0Count + 1 end

        local x, y = projectPosition(pos, floorIndex)
        x, y = smoothPosition(player, x, y)

        writeAt(x, y, marker, color)
        writeAt(x + 2, y, trimText(auth.user or player, 11), color)
      end
    end
  end

  for player in pairs(displayPositions) do
    if not activePlayers[player] then
      displayPositions[player] = nil
    end
  end

  return onlineCount, unknownCount, visitorCount, cl0Count
end

local function sendMapAlert(unknownCount)
  if unknownCount > 0 and os.clock() - lastUnknownAlertAt > alertCooldown then
    nodeClient.alert(tostring(unknownCount) .. " unrecognized player(s) on facility map", "warning")
    lastUnknownAlertAt = os.clock()
  end
end

local function mapLoop()
  while true do
    monitor.setVisible(false)

    clearScreen()
    drawFacilityFrame()

    local onlineCount, unknownCount, visitorCount, cl0Count = drawPlayers()

    drawHeader(onlineCount, unknownCount, visitorCount, cl0Count)
    drawLegend()
    sendMapAlert(unknownCount)

    monitor.setVisible(true)

    sleep(refreshSeconds)
  end
end

parallel.waitForAll(mapLoop, nodeClient.heartbeatLoop, nodeClient.securityListenLoop)
