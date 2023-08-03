-- Stops Termination ability
os.pullEvent = os.pullEventRaw
os.loadAPI("apis/cUtils.lua")

shell.run("cd /")
local w, h = cUtils.tGetSize()
-- Draw Menu Function
local nOption = 1

local function drawMenu()
    cUtils.tClear()
    cUtils.tSetTextColor(colors.yellow)
    cUtils.tSetCursorPos(1, 1)
    cUtils.tWrite("CookieOS 1.0.0")
    cUtils.tSetTextColor(colors.white)
    cUtils.tSetCursorPos(w - 11, 1)

    if nOption == 1 then
        cUtils.tWrite("Confirm")
    elseif nOption == 2 then
        cUtils.tWrite("Back")
    end
end

-- GUI
tClear()

local function drawFrontend()
    cUtils.centerPrint(math.floor(h / 2) - 3, "")
    cUtils.centerPrint(math.floor(h / 2) - 2, "Are you sure you want to uninstall?")
    cUtils.centerPrint(math.floor(h / 2) - 1, "")
    cUtils.centerPrint(math.floor(h / 2) - 0, nOption == 1 and "[ Confirm   ]" or " Confirm   ")
    cUtils.centerPrint(math.floor(h / 2) + 1, nOption == 2 and "[ Back      ]" or " Back      ")
end

-- Display
drawMenu()
drawFrontend()

while true do
    local _, key = os.pullEvent("key")

    -- Up
    if key == 265 then
        if nOption > 1 then
            nOption = nOption - 1
            drawMenu()
            drawFrontend()
        end
    elseif key == 264 then
        -- Down
        if nOption < 5 then
            nOption = nOption + 1
            drawMenu()
            drawFrontend()
        end
    elseif key == 257 then
        break
    end
end

cUtils.tClear()

-- Conditions
if nOption == 1 then
    cUtils.logToOS("[M:01] Navigating from " .. shell.getRunningProgram() .. " to ios/.uninstall" .. " at " .. cUtils.getTime())
    shell.run("ios/.uninstall")
else
    cUtils.logToOS("[M:01] Navigating from " .. shell.getRunningProgram() .. " to ios/.menu" .. " at " .. cUtils.getTime())
    shell.run("ios/.menu")
end