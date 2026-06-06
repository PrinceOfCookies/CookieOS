-- startup.lua
-- SubTerra Player Tracker
-- Data-only node: tracks/caches positions and answers lookup requests.
-- Section 1 | Column 1 | Row 6

local nodeClient = require("subterra_node_client")

nodeClient.init({
  modemSide = "back",
  protocol = "subterra_core",
  authProtocol = "subterra_auth",
  heartbeatSeconds = 5,
  node = "player_tracker",
  role = "security_data",
  location = "Section 1 | Column 1 | Row 6",
  services = {
    "players.cache",
    "players.lookup",
    "players.monitor",
  }
})

local playerDetector = peripheral.find("player_detector")
local monitor = peripheral.find("monitor")

if not playerDetector then error("No player detector found") end
if not monitor then error("No monitor found") end

local requestProtocol = "subterra_player_data"
local cachePath = "player_location_cache.txt"
local refreshSeconds = 5
local computerLocation = "Section 1 | Column 1 | Row 6"

local positionCache = {}

local bgColor = colors.black
local headerColor = colors.red
local textColor = colors.white

monitor.setTextScale(0.5)

if not rednet.isOpen("back") then
  rednet.open("back")
end

local function trimText(text, maxWidth)
  text = tostring(text or "")
  maxWidth = tonumber(maxWidth) or 0

  if #text <= maxWidth then return text end
  if maxWidth <= 3 then return text:sub(1, maxWidth) end

  return text:sub(1, maxWidth - 3) .. "..."
end

local function writeAt(x, y, text, color, bg)
  local width, height = monitor.getSize()
  if y < 1 or y > height then return end

  monitor.setCursorPos(math.max(1, x), y)
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

local function countTable(tbl)
  local count = 0
  for _ in pairs(tbl or {}) do count = count + 1 end
  return count
end

local function safeGetPlayers()
  local ok, players = pcall(playerDetector.getOnlinePlayers)
  if ok and type(players) == "table" then return players end
  return {}
end

local function safeGetPlayerPos(player)
  local ok, coords = pcall(playerDetector.getPlayerPos, player)
  if ok and type(coords) == "table" then return coords end
  return nil
end

local function saveCache()
  local file = fs.open(cachePath, "w")
  if not file then return end

  file.write(textutils.serialize(positionCache))
  file.close()
end

local function loadCache()
  if not fs.exists(cachePath) then return end

  local file = fs.open(cachePath, "r")
  if not file then return end

  local data = file.readAll()
  file.close()

  local ok, loaded = pcall(textutils.unserialize, data)

  if ok and type(loaded) == "table" then
    positionCache = loaded
  end
end

local function cachePlayerPosition(player, coords)
  if not player or not coords then return end

  positionCache[player] = {
    name = player,
    x = coords.x,
    y = coords.y,
    z = coords.z,
    health = coords.health,
    dimension = coords.dimension,
    lastSeen = os.time(),
  }
end

local function updatePositionCache()
  local players = safeGetPlayers()

  for _, player in ipairs(players) do
    local coords = safeGetPlayerPos(player)

    if coords then
      cachePlayerPosition(player, coords)
    end
  end

  saveCache()
  return players
end

local function findCachedOrOnlinePlayer(input)
  input = tostring(input or ""):lower()

  if input == "" then
    return nil, nil, "Usage: !where <name>"
  end

  local bestPlayer = nil
  local bestData = nil
  local bestScore = nil
  local bestOnline = false
  local matches = 0

  for _, player in ipairs(safeGetPlayers()) do
    local lowerName = tostring(player):lower()
    local startIndex = lowerName:find(input, 1, true)

    if startIndex then
      local coords = safeGetPlayerPos(player)

      if coords then
        cachePlayerPosition(player, coords)

        local score = startIndex + math.abs(#lowerName - #input)
        matches = matches + 1

        if not bestScore or score < bestScore then
          bestPlayer = player
          bestData = coords
          bestScore = score
          bestOnline = true
        end
      end
    end
  end

  for player, cached in pairs(positionCache) do
    local lowerName = tostring(player):lower()
    local startIndex = lowerName:find(input, 1, true)

    if startIndex then
      local score = startIndex + math.abs(#lowerName - #input) + 100

      if not bestScore or score < bestScore then
        bestPlayer = player
        bestData = cached
        bestScore = score
        bestOnline = false
      end
    end
  end

  if not bestPlayer then
    return nil, nil, "No online or cached player matches: " .. input
  end

  saveCache()
  return bestPlayer, bestData, nil, bestOnline, matches
end

local function drawHeader()
  local width = monitor.getSize()
  local label = os.getComputerLabel() or ("Computer " .. os.getComputerID())

  monitor.setCursorPos(1, 1)
  monitor.setBackgroundColor(headerColor)
  monitor.write(string.rep(" ", width))

  writeCentered(1, label, colors.white, headerColor)
  writeCentered(3, "Player Tracker", colors.lime, bgColor)
  writeCentered(4, computerLocation, colors.lightBlue, bgColor)
end

local function formatPlayerLine(player, coords)
  return string.format(
    "%s [%s] %s %s %s",
    tostring(player),
    tostring(math.floor(tonumber(coords.health) or 0)),
    formatCoord(coords.x),
    formatCoord(coords.y),
    formatCoord(coords.z)
  )
end

local function drawPlayerCoords()
  clearScreen()
  drawHeader()

  local players = updatePositionCache()
  local _, height = monitor.getSize()

  local overworld = {}
  local nether = {}
  local other = {}

  for _, player in ipairs(players) do
    local coords = safeGetPlayerPos(player)

    if coords then
      local dim = tostring(coords.dimension or "unknown")
      local line = formatPlayerLine(player, coords)

      if dim == "minecraft:overworld" then
        table.insert(overworld, line)
      elseif dim == "minecraft:the_nether" then
        table.insert(nether, line)
      else
        table.insert(other, line .. " (" .. formatDimension(dim) .. ")")
      end
    else
      table.insert(other, tostring(player) .. " coords unavailable")
    end
  end

  writeAt(1, 6, "Online: " .. #players .. " | Cached: " .. countTable(positionCache), colors.lightGray)

  local y = 8

  writeAt(1, y, "Overworld", colors.green)
  y = y + 1

  if #overworld == 0 then
    writeAt(1, y, "No players", colors.gray)
    y = y + 2
  else
    for _, line in ipairs(overworld) do
      writeAt(1, y, line)
      y = y + 1
      if y > height then return end
    end
    y = y + 1
  end

  writeAt(1, y, "Nether", colors.red)
  y = y + 1

  if #nether == 0 then
    writeAt(1, y, "No players", colors.gray)
    y = y + 2
  else
    for _, line in ipairs(nether) do
      writeAt(1, y, line)
      y = y + 1
      if y > height then return end
    end
    y = y + 1
  end

  if #other > 0 and y <= height then
    writeAt(1, y, "Other / Unknown", colors.yellow)
    y = y + 1

    for _, line in ipairs(other) do
      writeAt(1, y, line, colors.lightGray)
      y = y + 1
      if y > height then return end
    end
  end
end

local function dataServerLoop()
  while true do
    local senderId, packet = rednet.receive(requestProtocol)

    if type(packet) == "table" and packet.app == "subterra" then
      if packet.type == "player_lookup" then
        local player, coords, errorMessage, isOnline, matches = findCachedOrOnlinePlayer(packet.query)

        rednet.send(senderId, {
          app = "subterra",
          type = "player_lookup_response",
          requestId = packet.requestId,
          ok = player ~= nil,
          player = player,
          coords = coords,
          error = errorMessage,
          isOnline = isOnline,
          matches = matches,
        }, requestProtocol)
      elseif packet.type == "player_cache_count" then
        rednet.send(senderId, {
          app = "subterra",
          type = "player_cache_count_response",
          requestId = packet.requestId,
          online = #safeGetPlayers(),
          cached = countTable(positionCache),
        }, requestProtocol)
      end
    end
  end
end

local function monitorLoop()
  while true do
    drawPlayerCoords()
    sleep(refreshSeconds)
  end
end

local function trackerHeartbeatLoop()
  while true do
    local onlineCount = #safeGetPlayers()
    local status = onlineCount > 0 and ("tracking " .. onlineCount .. " online") or "no players online"

    nodeClient.heartbeat(status)
    sleep(5)
  end
end

loadCache()
parallel.waitForAll(monitorLoop, dataServerLoop, trackerHeartbeatLoop, nodeClient.securityListenLoop)
