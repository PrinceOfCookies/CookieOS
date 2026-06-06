-- startup.lua
-- Sender computer
-- Local monitor: small status screen from your pasted code
-- Remote receiver monitor: gets the big SubTerra screen over modem channel 106

local monitor = peripheral.find("monitor")
local modem = peripheral.wrap("back")

if not monitor then error("No monitor found") end
if not modem then error("No modem on back") end

local channel = 106
local computerLocation = "Section 2 | Column 2 | Row 3"
local facilityStatus = "UNDER CONSTRUCTION"

modem.open(channel)

local bgColor = colors.black
local accentColor = colors.red
local textColor = colors.white

monitor.setTextScale(0.5)
monitor.setBackgroundColor(bgColor)
monitor.clear()

local width = monitor.getSize()
local label = os.getComputerLabel() or ("Computer " .. os.getComputerID())

local function writeCentered(y, text, color, bg)
  local x = math.floor((width - #text) / 2) + 1

  monitor.setCursorPos(x, y)
  monitor.setTextColor(color)
  monitor.setBackgroundColor(bg)
  monitor.write(text)
end

local function fitText(text, maxWidth)
  if #text <= maxWidth then
    return text
  end

  return text:sub(1, maxWidth - 3) .. "..."
end

local function drawLocalScreen(statusText)
  monitor.setBackgroundColor(bgColor)
  monitor.clear()

  monitor.setCursorPos(1, 1)
  monitor.setBackgroundColor(accentColor)
  monitor.clearLine()

  writeCentered(1, label, textColor, accentColor)

  monitor.setBackgroundColor(bgColor)
  writeCentered(3, fitText("SubTerra Monitor", width), colors.lime, bgColor)
  writeCentered(5, fitText(computerLocation, width), colors.lightBlue, bgColor)
  writeCentered(7, "Status: " .. facilityStatus, colors.yellow, bgColor)
  writeCentered(9, "Channel: " .. channel, colors.lightGray, bgColor)
  writeCentered(11, "Modem: Back", colors.gray, bgColor)

  if statusText then
    monitor.setCursorPos(1, 13)
    monitor.clearLine()
    writeCentered(13, fitText(statusText, width), colors.white, bgColor)
  end
end

local function getRemotePayload()
  local timeText = textutils.formatTime(os.time(), true)
  local dateText = os.date("%d/%m/%Y")

  return {
    type = "subterra_display",
    textScale = 1,
    backgroundColor = colors.black,

    lines = {
      { type = "text", text = "[ SUBTERRA : SITE 6 ]", color = colors.cyan },
      { type = "text", text = "UNDERGROUND FACILITY", color = colors.white },
      { type = "line", color = colors.cyan },
      { type = "text", text = "WELCOME, FLOOR 1 - MAIN ENTRANCE", color = colors.white },
      { type = "text", text = timeText .. "  |  " .. dateText, color = colors.gray },
      { type = "line", color = colors.gray },
      { type = "text", text = "FACILITY STATUS: [ " .. facilityStatus .. " ]", color = colors.yellow },
      { type = "text", text = "STATUS STATED:   [ " .. facilityStatus .. " ]", color = colors.yellow },
      { type = "text", text = "POWER:           [ OFFLINE ]", color = colors.red },
      { type = "text", text = "COMMS:           [ NO SIGNAL ]", color = colors.red },
      { type = "text", text = "PERSONNEL:       [ 0 ]", color = colors.white },
      { type = "text", text = "LAST INCIDENT:   [ 47 DAYS AGO ]", color = colors.white },
      { type = "text", text = "AUTH LEVEL:      [ RESTRICTED ]", color = colors.yellow },
      { type = "line", color = colors.gray },
      { type = "text", text = "STRAWHAT FANCLUB ADMINISTRATION", color = colors.gray },
    }
  }
end

local function sendRemoteScreen()
  while true do
    modem.transmit(channel, channel, getRemotePayload())
    sleep(1)
  end
end

local function updateLocalStatus()
  drawLocalScreen("Sending display data...")

  while true do
    local _, _, recvChannel, _, message = os.pullEvent("modem_message")

    if recvChannel == channel and type(message) ~= "table" then
      drawLocalScreen(tostring(message))
    end
  end
end

parallel.waitForAny(sendRemoteScreen, updateLocalStatus)
