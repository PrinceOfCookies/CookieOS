package.path = package.path .. ";/apis/*.lua;/apis/*/init.lua;/apis/cosUtils.lua"
_G.cosUtils = require("cosUtils")
_G.cosv = "CookieOS v2.2"
_G.developmentMode = true

if not developmentMode then
    os.pullEvent = os.pullEventRaw
end

local monitor = cosUtils.isMonitorHere()

local function loadingText(device)
    local slowPrint = monitor and cosUtils.monSlowPrint or textutils.slowPrint

    if device.setTextScale then
        device.setTextScale(0.5)
    end

    cosUtils.resetScreen(device)
    if not developmentMode then
        device.setTextColor(colors.yellow)
        slowPrint(cosv)
        os.sleep(0.5)
        device.setCursorPos(1, 2)
        -- Print out all the files being loaded, along with the function names in the cosUtils api
        local y = 3
        local i = 0
        for k, v in pairs(cosUtils) do
            if type(v) == "function" then
                i = i + 1
                -- get the func name
                local funcName = k
                if funcName == " " then funcName = "Unknown" end
                slowPrint("Loading func from cosUtils: " .. funcName, monitor and 0.1 or 252)extColor(colors.white)
            end

            y = y + 1
            device.setCursorPos(1, y)
        end
    else
        local w, h = device.getSize()

        device.setTextColor(colors.yellow)
        cosUtils.centerPrint(math.floor(h / 2) - 1, w, cosv)

        cosUtils.loadingBar(term, (h / 2) + 2, colors.blue)
    end

    os.sleep(1)

    device.setBackgroundColor(colors.black)
    device.clear()
    shell.run("startup/replacements.lua")
    shell.run(".menu")
end

loadingText(monitor and monitor or term)