-- startup.lua
-- SubTerra Personnel Server
-- Displays and serves registered Auth users.
-- Does not own the database. Auth Server is still source of truth.

local nodeClient = require("subterra_node_client")

nodeClient.init({
  modemSide = "back",
  protocol = "subterra_core",
  authProtocol = "subterra_auth",
  heartbeatSeconds = 5,
  node = "personnel_server",
  role = "personnel",
  location = "Server Room",
  services = {
    "personnel.display",
    "personnel.list",
    "personnel.search",
  }
})

local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found") end

monitor.setTextScale(0.5)

local personnelProtocol = "subterra_personnel"
local authProtocol = "subterra_auth"

local users = {}
local lastRefreshAt = 0
local lastError = nil
local refreshSeconds = 10

local function trimText(text, maxWidth)
  text = tostring(text or "")
  maxWidth = tonumber(maxWidth) or #text

  if #text <= maxWidth then return text end
  if maxWidth <= 3 then return text:sub(1, maxWidth) end

  return text:sub(1, maxWidth - 3) .. "..."
end

local function writeLine(y, text, color, bg)
  local width, height = monitor.getSize()

  if y < 1 or y > height then return end

  monitor.setCursorPos(1, y)
  monitor.setBackgroundColor(bg or colors.black)
  monitor.setTextColor(color or colors.white)
  monitor.clearLine()
  monitor.write(trimText(text, width))
end

local function writeCentered(y, text, color, bg)
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

local function makeRequestId()
  return tostring(os.getComputerID()) .. "-" .. tostring(os.clock()) .. "-" .. tostring(math.random(1000, 9999))
end

local function requestAuthUserList(actor)
  local requestId = makeRequestId()

  rednet.broadcast({
    app = "subterra",
    type = "auth_list_users",
    requestId = requestId,
    data = {
      actor = actor or "lifeline4603",
      requestId = requestId,
    },
  }, authProtocol)

  local startedAt = os.clock()

  while os.clock() - startedAt < 3 do
    local _, response = rednet.receive(authProtocol, 3)

    if type(response) == "table"
      and response.app == "subterra"
      and response.type == "auth_list_users_response"
      and response.requestId == requestId then
      return response
    end
  end

  return {
    ok = false,
    reason = "Auth server timeout",
    users = {},
  }
end

local function refreshUsers()
  local response = requestAuthUserList("lifeline4603")

  if response.ok then
    users = response.users or {}
    lastRefreshAt = os.clock()
    lastError = nil
  else
    lastError = response.reason or "Unknown auth error"
  end
end

local function getUserColor(user)
  local status = tostring(user.status or ""):lower()
  local role = tostring(user.role or ""):lower()
  local clearance = tonumber(user.clearance) or 0

  if status == "fired" then return colors.red end
  if role:find("visitor", 1, true) then return colors.yellow end
  if clearance == 0 then return colors.orange end
  if clearance >= 5 then return colors.purple end
  if clearance >= 4 then return colors.lime end

  return colors.white
end

local function draw()
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()

  monitor.setCursorPos(1, 1)
  monitor.setBackgroundColor(colors.red)
  monitor.clearLine()
  writeCentered(1, "SUBTERRA PERSONNEL", colors.white, colors.red)

  writeCentered(3, "Registered Users", colors.lime)
  writeLine(5, "Users: " .. tostring(#users) .. " | Last Sync: " .. tostring(math.floor(os.clock() - lastRefreshAt)) .. "s", colors.lightGray)

  if lastError then
    writeLine(6, "Auth Error: " .. tostring(lastError), colors.red)
  else
    writeLine(6, "Auth: ONLINE", colors.lime)
  end

  writeLine(8, "CL   Name              Role              Status", colors.yellow)

  local y = 9
  local _, height = monitor.getSize()

  for _, user in ipairs(users) do
    if y > height then break end

    writeLine(
      y,
      string.format(
        "%-4s %-17s %-17s %s",
        tostring(user.clearanceLabel or ("CL" .. tostring(user.clearance or 0))),
        trimText(user.name, 17),
        trimText(user.role or "Unknown", 17),
        tostring(user.status or "Unknown")
      ),
      getUserColor(user)
    )

    y = y + 1
  end
end

local function lowerContains(text, query)
  return tostring(text or ""):lower():find(tostring(query or ""):lower(), 1, true) ~= nil
end

local function filterUsers(filter, query)
  filter = tostring(filter or "all"):lower()
  query = tostring(query or "")

  local result = {}

  for _, user in ipairs(users) do
    local include = true
    local role = tostring(user.role or ""):lower()
    local status = tostring(user.status or ""):lower()
    local clearanceLabel = tostring(user.clearanceLabel or ("CL" .. tostring(user.clearance or 0))):lower()

    if filter == "fired" then
      include = status == "fired"
    elseif filter == "visitors" or filter == "visitor" then
      include = role:find("visitor", 1, true) ~= nil
    elseif filter:match("^cl%d$") then
      include = clearanceLabel == filter
    elseif filter == "search" then
      include = lowerContains(user.name, query)
        or lowerContains(user.role, query)
        or lowerContains(user.status, query)
    end

    if include then
      table.insert(result, user)
    end
  end

  return result
end

local function handleRequest(senderId, packet)
  if type(packet) ~= "table" or packet.app ~= "subterra" then return end

  if packet.type == "personnel_list_request" then
    local requestId = packet.requestId
    local filtered = filterUsers(packet.filter, packet.query)

    rednet.send(senderId, {
      app = "subterra",
      type = "personnel_list_response",
      requestId = requestId,
      ok = true,
      users = filtered,
      total = #users,
      error = lastError,
    }, personnelProtocol)
  elseif packet.type == "personnel_refresh_request" then
    refreshUsers()

    rednet.send(senderId, {
      app = "subterra",
      type = "personnel_refresh_response",
      requestId = packet.requestId,
      ok = lastError == nil,
      error = lastError,
      total = #users,
    }, personnelProtocol)
  end
end

local function refreshLoop()
  refreshUsers()

  while true do
    sleep(refreshSeconds)
    refreshUsers()
  end
end

local function drawLoop()
  while true do
    draw()
    sleep(1)
  end
end

local function receiveLoop()
  while true do
    local senderId, packet = rednet.receive(personnelProtocol, 1)

    if senderId then
      handleRequest(senderId, packet)
    end
  end
end

parallel.waitForAll(refreshLoop, drawLoop, receiveLoop, nodeClient.heartbeatLoop, nodeClient.securityListenLoop)
