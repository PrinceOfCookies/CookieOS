tSetCursorPos = term.setCursorPos             -- Set Cursor Position
tClearLine = term.clearLine                   -- Clear Line
tWrite = term.write                           -- Write
tClear = term.clear                           -- Clear
tGetSize = term.getSize                       -- Get Size
tSetTextColor = term.setTextColor             -- Set Text Color
tGetTextColor = term.getTextColor             -- Get Text Color
tSetBackgroundColor = term.setBackgroundColor -- Set Background Color
slowPrint = textutils.slowPrint               -- Slow Print
sleep = os.sleep                              -- Sleep
os.loadAPI("apis/utils.lua")
local w, h = tGetSize()

function centerPrint(yPos, str)
    local x = math.floor((w - string.len(str)) / 2)
    tSetCursorPos(x, yPos)
    tClearLine()
    tWrite(str)
end

function delete(name, dir)
    if dir and fs.isDir(name) then
        slowPrint("Deleting directory: " .. name)
        slowPrint("###################")
        sleep(0.5)
        fs.delete(name)
        print("Directory: " .. name .. " deleted")
    else
        slowPrint("Deleting file: " .. name)
        slowPrint("###################")
        sleep(0.5)
        fs.delete(name)
        print("File: " .. name .. " deleted")
    end
end

function displayAccessGranted(msg)
    tClear()
    local message = tostring(msg)
    local x, y = math.floor(w / 2) - math.floor(string.len(message) / 2), math.floor(h / 2)

    tSetBackgroundColor(colors.green)

    for i = 1, h do
        tSetCursorPos(1, i)
        tWrite(string.rep(" ", w))
    end

    tSetCursorPos(x, y)
    tSetTextColor(colors.black)
    tWrite(message)

    sleep(1)

    tSetBackgroundColor(colors.black)
    tClear()

    tSetCursorPos(1, 1)
end

function displayAccessDenied(msg)
    tClear()
    local message = tostring(msg)
    local x, y = math.floor(w / 2) - math.floor(string.len(message) / 2), math.floor(h / 2)

    tSetBackgroundColor(colors.red)

    for i = 1, h do
        tSetCursorPos(1, i)
        tWrite(string.rep(" ", w))
    end

    tSetCursorPos(x, y)
    tSetTextColor(colors.black)
    tWrite(message)

    sleep(1)

    tSetBackgroundColor(colors.black)
    tClear()

    tSetCursorPos(1, 1)
    os.reboot()
end

function logToOS(msg)
    local mode = fs.exists("OS.log") and "a" or "w"
    local file = fs.open("OS.log", mode)

    file.write(msg .. "\n")

    local size = fs.getSize("OS.log")
    file.close()

    file = fs.open("OS.log", "r")
    local content = file.readAll()
    file.close()

    if size >= 10000 then
        local filee = fs.open("ios/security/.keys", "r")
        local _ = filee.readLine()
        local _ = filee.readLine()
        local encryptKey = filee.readLine()

        local newcontnet = utils.Package(encryptKey, content)

        file = fs.open("OS.log", "w")
        file.write(newcontnet .. "\n")
        file.close()
    elseif size >= 50000 then
        file = fs.open("OS.log", "w")
        file.write("[A:22] Logs reached 50,000 bytes. Deleting logs at " .. getTime .. "\n")
        file.close()
    end
end

function getTime()
    local date = os.date("*t")
    local year = tostring(date.year)
    local month = tostring(date.month)
    local day = tostring(date.day)
    local hour = tostring(date.hour)
    local minute = tostring(date.min)
    local second = tostring(date.sec)

    if string.len(month) == 1 then
        month = "0" .. month
    end

    if string.len(day) == 1 then
        day = "0" .. day
    end

    if string.len(hour) == 1 then
        hour = "0" .. hour
    end

    if string.len(minute) == 1 then
        minute = "0" .. minute
    end

    if string.len(second) == 1 then
        second = "0" .. second
    end

    return year .. "-" .. month .. "-" .. day .. " | " .. hour .. ":" .. minute .. ":" .. second
end
