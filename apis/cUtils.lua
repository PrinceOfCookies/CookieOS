local expect = require("cc.expect").expect
local bitXor = bit.bxor
local bitAnd = bit.band
local bitOr = bit.bor
local bitNot = bit.bnot
local bitShiftLeft = bit.blshift
local bitShiftRight = bit.brshift
local spack, sunpack = string.pack, string.unpack
local byte, char, concat = string.byte, string.char, table.concat
local funcCount = 0
local type = type
local sub = string.sub
local tconcat = table.concat
local w, _ = term.getSize()
local drawMenuWin = window.create(term.current(), 1, 1, w, 2, false)
local basedictcompress = {}
local basedictdecompress = {}
local cosUtils = {}

settings.define("timeFormat", {
    description = "The display format for the time on menu and other places (12, or 24)",
    default = "12",
    type = "string",
})

function string.split(input, delimiter)
    local result = {}
    local pattern = string.format("([^%s]+)", delimiter)

    for word in string.gmatch(input, pattern) do
        table.insert(result, word)
    end

    return result
end

function string.trim(input)
    return input:match("^%s*(.-)%s*$")
end

function string.startswith(input, start)
    return input:sub(1, #start) == start
end

function string.endswith(input, ending)
    return ending == "" or input:sub(-#ending) == ending
end

function string.join(delimiter, list)
    return table.concat(list, delimiter)
end

function string.replace(input, old, new)
    return input:gsub(old, new)
end

function string.toUpper(input)
    return input:upper()
end

function string.toLower(input)
    return input:lower()
end

function string.reverse(input)
    return input:reverse()
end

function string.contains(input, substring)
    return input:find(substring, 1, true) ~= nil
end

function string.isEmpty(input)
    return input:match("^%s*$") ~= nil
end

function cosUtils.colorLerp(startColor, endColor, speed)
    local r = startColor[1] + (endColor[1] - startColor[1]) * math.min(speed, 1)
    local g = startColor[2] + (endColor[2] - startColor[2]) * math.min(speed, 1)
    local b = startColor[3] + (endColor[3] - startColor[3]) * math.min(speed, 1)

    return {r, g, b}
end


local function FF(a, b, c, d, x, s, ac)
    a = bitAnd(a + bitOr(bitAnd(b, c), bitAnd(bitNot(b), d)) + x + ac, 0xffffffff)
    a = bitAnd(bitOr(bitShiftLeft(a, s), bitShiftRight(a, 32 - s)), 0xffffffff)
    a = bitAnd(a + b, 0xffffffff)

    return a
end

local function GG(a, b, c, d, x, s, ac)
    a = bitAnd(a + bitOr(bitAnd(b, d), bitAnd(c, bitNot(d))) + x + ac, 0xffffffff)
    a = bitAnd(bitOr(bitShiftLeft(a, s), bitShiftRight(a, 32 - s)), 0xffffffff)
    a = bitAnd(a + b, 0xffffffff)

    return a
end

local function HH(a, b, c, d, x, s, ac)
    a = bitAnd(a + bitXor(bitXor(b, c), d) + x + ac, 0xffffffff)
    a = bitAnd(bitOr(bitShiftLeft(a, s), bitShiftRight(a, 32 - s)), 0xffffffff)
    a = bitAnd(a + b, 0xffffffff)

    return a
end

local function II(a, b, c, d, x, s, ac)
    a = bitAnd(a + bitXor(c, bitOr(b, bitNot(d))) + x + ac, 0xffffffff)
    a = bitAnd(bitOr(bitShiftLeft(a, s), bitShiftRight(a, 32 - s)), 0xffffffff)
    a = bitAnd(a + b, 0xffffffff)

    return a
end

local function transform(state, input, i, t)
    -- process the 64-byte input block in string "input" at offset "i"
    -- t is a uint32[16] array. It is passed as a parameter
    -- for performance reasons
    --
    local a, b, c, d = state[1], state[2], state[3], state[4]

    -- load array
    for j = 1, 16 do
        t[j] = sunpack("<I4", input, i)
        i = i + 4
    end

    -- Round 1
    a = FF(a, b, c, d, t[1], 7, 0xd76aa478)
    d = FF(d, a, b, c, t[2], 12, 0xe8c7b756)
    c = FF(c, d, a, b, t[3], 17, 0x242070db)
    b = FF(b, c, d, a, t[4], 22, 0xc1bdceee)
    a = FF(a, b, c, d, t[5], 7, 0xf57c0faf)
    d = FF(d, a, b, c, t[6], 12, 0x4787c62a)
    c = FF(c, d, a, b, t[7], 17, 0xa8304613)
    b = FF(b, c, d, a, t[8], 22, 0xfd469501)
    a = FF(a, b, c, d, t[9], 7, 0x698098d8)
    d = FF(d, a, b, c, t[10], 12, 0x8b44f7af)
    c = FF(c, d, a, b, t[11], 17, 0xffff5bb1)
    b = FF(b, c, d, a, t[12], 22, 0x895cd7be)
    a = FF(a, b, c, d, t[13], 7, 0x6b901122)
    d = FF(d, a, b, c, t[14], 12, 0xfd987193)
    c = FF(c, d, a, b, t[15], 17, 0xa679438e)
    b = FF(b, c, d, a, t[16], 22, 0x49b40821)
    -- Round 2
    a = GG(a, b, c, d, t[2], 5, 0xf61e2562)
    d = GG(d, a, b, c, t[7], 9, 0xc040b340)
    c = GG(c, d, a, b, t[12], 14, 0x265e5a51)
    b = GG(b, c, d, a, t[1], 20, 0xe9b6c7aa)
    a = GG(a, b, c, d, t[6], 5, 0xd62f105d)
    d = GG(d, a, b, c, t[11], 9, 0x2441453)
    c = GG(c, d, a, b, t[16], 14, 0xd8a1e681)
    b = GG(b, c, d, a, t[5], 20, 0xe7d3fbc8)
    a = GG(a, b, c, d, t[10], 5, 0x21e1cde6)
    d = GG(d, a, b, c, t[15], 9, 0xc33707d6)
    c = GG(c, d, a, b, t[4], 14, 0xf4d50d87)
    b = GG(b, c, d, a, t[9], 20, 0x455a14ed)
    a = GG(a, b, c, d, t[14], 5, 0xa9e3e905)
    d = GG(d, a, b, c, t[3], 9, 0xfcefa3f8)
    c = GG(c, d, a, b, t[8], 14, 0x676f02d9)
    b = GG(b, c, d, a, t[13], 20, 0x8d2a4c8a)
    -- Round 3
    a = HH(a, b, c, d, t[6], 4, 0xfffa3942)
    d = HH(d, a, b, c, t[9], 11, 0x8771f681)
    c = HH(c, d, a, b, t[12], 16, 0x6d9d6122)
    b = HH(b, c, d, a, t[15], 23, 0xfde5380c)
    a = HH(a, b, c, d, t[2], 4, 0xa4beea44)
    d = HH(d, a, b, c, t[5], 11, 0x4bdecfa9)
    c = HH(c, d, a, b, t[8], 16, 0xf6bb4b60)
    b = HH(b, c, d, a, t[11], 23, 0xbebfbc70)
    a = HH(a, b, c, d, t[14], 4, 0x289b7ec6)
    d = HH(d, a, b, c, t[1], 11, 0xeaa127fa)
    c = HH(c, d, a, b, t[4], 16, 0xd4ef3085)
    b = HH(b, c, d, a, t[7], 23, 0x4881d05)
    a = HH(a, b, c, d, t[10], 4, 0xd9d4d039)
    d = HH(d, a, b, c, t[13], 11, 0xe6db99e5)
    c = HH(c, d, a, b, t[16], 16, 0x1fa27cf8)
    b = HH(b, c, d, a, t[3], 23, 0xc4ac5665)
    -- Round 4
    a = II(a, b, c, d, t[1], 6, 0xf4292244)
    d = II(d, a, b, c, t[8], 10, 0x432aff97)
    c = II(c, d, a, b, t[15], 15, 0xab9423a7)
    b = II(b, c, d, a, t[6], 21, 0xfc93a039)
    a = II(a, b, c, d, t[13], 6, 0x655b59c3)
    d = II(d, a, b, c, t[4], 10, 0x8f0ccc92)
    c = II(c, d, a, b, t[11], 15, 0xffeff47d)
    b = II(b, c, d, a, t[2], 21, 0x85845dd1)
    a = II(a, b, c, d, t[9], 6, 0x6fa87e4f)
    d = II(d, a, b, c, t[16], 10, 0xfe2ce6e0)
    c = II(c, d, a, b, t[7], 15, 0xa3014314)
    b = II(b, c, d, a, t[14], 21, 0x4e0811a1)
    a = II(a, b, c, d, t[5], 6, 0xf7537e82)
    d = II(d, a, b, c, t[12], 10, 0xbd3af235)
    c = II(c, d, a, b, t[3], 15, 0x2ad7d2bb)
    b = II(b, c, d, a, t[10], 21, 0xeb86d391)
    state[1] = bitAnd(state[1] + a, 0xffffffff)
    state[2] = bitAnd(state[2] + b, 0xffffffff)
    state[3] = bitAnd(state[3] + c, 0xffffffff)
    state[4] = bitAnd(state[4] + d, 0xffffffff)
end

local function md5(input)
    local state = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476}

    local inputlen = #input
    local inputbits = inputlen * 8 -- input length in bits
    local r = inputlen -- number of unprocessed bytes
    local i = 1 -- index in input string

    local ibt = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

    while r >= 64 do
        -- process block
        transform(state, input, i, ibt)
        i = i + 64
        r = r - 64
    end

    local lastblock -- the rest of input .. some padding .. inputbits
    local padlen -- padding length in bytes

    if r < 56 then
        padlen = 55 - r
    else
        padlen = 119 - r
    end

    lastblock = input:sub(i) .. "\x80" .. ("\0"):rep(padlen) .. spack("<I8", inputbits) -- remaining input --padding -- length in bits
    assert(#lastblock == 64 or #lastblock == 128)
    transform(state, lastblock, 1, ibt)

    if #lastblock == 128 then
        transform(state, lastblock, 65, ibt)
    end

    -- return the digest
    local digest = spack("<I4I4I4I4", state[1], state[2], state[3], state[4])

    return digest
end

local function keysched(key)
    assert(#key == 16, "key must be a 16-byte string")
    local s = {}
    local j, ii, jj

    for i = 0, 255 do
        s[i + 1] = i
    end

    j = 0

    for i = 0, 255 do
        ii = i + 1
        j = bitAnd(j + s[ii] + byte(key, (i % 16) + 1), 0xff)
        jj = j + 1
        s[ii], s[jj] = s[jj], s[ii]
    end

    return s
end

local function step(s, i, j)
    i = bitAnd(i + 1, 0xff)
    local ii = i + 1
    j = bitAnd(j + s[ii], 0xff)
    local jj = j + 1
    s[ii], s[jj] = s[jj], s[ii]
    local k = s[bitAnd(s[ii] + s[jj], 0xff) + 1]

    return s, i, j, k
end

local function rc4raw(key, plain)
    local s = keysched(key)
    local i, j = 0, 0
    local k
    local t = {}

    for n = 1, #plain do
        s, i, j, k = step(s, i, j)
        t[n] = char(bitXor(byte(plain, n), k))
    end

    return concat(t)
end

local function rc4(key, plain, drop)
    drop = drop or 256
    local s = keysched(key)
    local i, j = 0, 0
    local k
    local t = {}

    for _ = 1, drop do
        s, i, j = step(s, i, j)
    end

    for n = 1, #plain do
        s, i, j, k = step(s, i, j)
        t[n] = char(bitXor(byte(plain, n), k))
    end

    return concat(t)
end

for i = 0, 255 do
    local ic, iic = char(i), char(i, 0)
    basedictcompress[ic] = iic
    basedictdecompress[iic] = ic
end

local function isValidHash(expected, actual)
    return expected == actual
end

local function dictAddA(str, dict, a, b)
    if a >= 256 then
        a, b = 0, b + 1

        if b >= 256 then
            dict = {}
            b = 1
        end
    end

    dict[str] = char(a, b)
    a = a + 1

    return dict, a, b
end

local function dictAddB(str, dict, a, b)
    if a >= 256 then
        a, b = 0, b + 1

        if b >= 256 then
            dict = {}
            b = 1
        end
    end

    dict[char(a, b)] = str
    a = a + 1

    return dict, a, b
end

function RMA()
    local template = "0xXXXXXXXX"
    local address = string.gsub(template, "X", function(c) return string.format("%X", math.random(0, 15)) end)

    return address
end

function cosUtils.compress(input, ignoreSize)
    if type(input) ~= "string" then return nil, "string expected, got " .. type(input) end
    local len = #input
    if len <= 1 then return "u" .. input end
    local dict = {}
    local a, b = 0, 1

    local result = {"c"}

    local resultlen = 1
    local n = 2
    local word = ""

    for i = 1, len do
        local c = sub(input, i, i)
        local wc = word .. c

        if not (basedictcompress[wc] or dict[wc]) then
            local write = basedictcompress[word] or dict[word]
            if not write then return nil, "algorithm error, could not fetch word" end
            result[n] = write
            resultlen = resultlen + #write
            n = n + 1
            if len <= resultlen and ignoreSize ~= true then return "u" .. input end
            dict, a, b = dictAddA(wc, dict, a, b)
            word = c
        else
            word = wc
        end
    end

    result[n] = basedictcompress[word] or dict[word]
    resultlen = resultlen + #result[n]
    n = n + 1
    if len <= resultlen and ignoreSize ~= true then return "u" .. input end

    return tconcat(result)
end

function cosUtils.decompress(input)
    if type(input) ~= "string" then return nil, "string expected, got " .. type(input) end
    if #input < 1 then return nil, "invalid input - not a compressed string" end
    local control = sub(input, 1, 1)

    if control == "u" then
        return sub(input, 2)
    elseif control ~= "c" then
        return nil, "invalid input - not a compressed string"
    end

    input = sub(input, 2)
    local len = #input
    if len < 2 then return nil, "invalid input - not a compressed string" end
    local dict = {}
    local a, b = 0, 1
    local result = {}
    local n = 1
    local last = sub(input, 1, 2)
    result[n] = basedictdecompress[last] or dict[last]
    n = n + 1

    for i = 3, len, 2 do
        local code = sub(input, i, i + 1)
        local lastStr = basedictdecompress[last] or dict[last]
        if not lastStr then return nil, "could not find last from dict. Invalid input?" end
        local toAdd = basedictdecompress[code] or dict[code]

        if toAdd then
            result[n] = toAdd
            n = n + 1
            dict, a, b = dictAddB(lastStr .. sub(toAdd, 1, 1), dict, a, b)
        else
            local tmp = lastStr .. sub(lastStr, 1, 1)
            result[n] = tmp
            n = n + 1
            dict, a, b = dictAddB(tmp, dict, a, b)
        end

        last = code
    end

    return tconcat(result)
end

function cosUtils.fromhex(str)
    return str:gsub("..", function(cc) return string.char(tonumber(cc, 16)) end)
end

function cosUtils.tohex(str)
    return str:gsub(".", function(c) return string.format("%02X", string.byte(c)) end)
end

function cosUtils.Package(KEY, data)
    if type(KEY) ~= "string" then return nil, "string expected, got " .. type(KEY) end
    local encryptedData = rc4(KEY, data) -- encrypt data
    local compressedData = cosUtils.compress(encryptedData) -- compress data
    compressedData = compressedData .. md5(KEY .. compressedData) -- add md5 hash to compressed data to verify integrity

    return compressedData
end

function cosUtils.isPackaged(KEY, data)
    if #data < 17 then return false, nil end
    local compressedData = data:sub(1, -17)
    local md5Hash = data:sub(-16)
    if isValidHash(md5(KEY .. compressedData), md5Hash) then return true, compressedData end

    for i = 1, #data - 16 do
        local partCompressedData = data:sub(1, i)
        local partMd5Hash = data:sub(i + 1, i + 16)
        if isValidHash(md5(KEY .. partCompressedData), partMd5Hash) then return true, partCompressedData end
    end

    return false, nil
end

function cosUtils.interleave(data1, data2)
    local len1 = #data1
    local len2 = #data2
    local maxLen = math.max(len1, len2)
    local result = {}

    for i = 1, maxLen do
        if i <= len1 then
            table.insert(result, data1:sub(i, i))
        end

        if i <= len2 then
            table.insert(result, data2:sub(i, i))
        end
    end

    return table.concat(result)
end

function cosUtils.UnPackage(KEY, data)
    local results = {}
    local segmentLength = 16 -- Length of the checksum plus encrypted segment
    local dataLength = #data
    local index = 1

    while index <= dataLength do
        local segmentEnd = math.min(index + segmentLength - 1, dataLength)
        local segment = data:sub(index, segmentEnd)
        local isPackaged, compressedData = cosUtils.isPackaged(KEY, segment)

        if isPackaged then
            print("Valid segment found starting at index " .. index)
            local decompressedData, err = cosUtils.decompress(compressedData)

            if decompressedData then
                table.insert(results, decompressedData)
            else
                print("Decompression error for segment starting at index " .. index .. ": " .. (err or "unknown error"))
            end
        else
            print("Segment starting at index " .. index .. " is not packaged.")
        end

        index = index + segmentLength
    end

    local combinedResults = table.concat(results)

    if #combinedResults > 0 then
        return combinedResults, nil
    else
        return nil, "No valid data found"
    end
end

-- Globals for Computercraft
if os and os.version then
    Compress = compress
    Decompress = decompress
    Encrypt = rc4
    Decrypt = rc4
    MD5 = md5
end

function cosUtils.fileCount(directory)
    local count = 0
    local items = fs.list(directory)

    for _, item in ipairs(items) do
        local path = fs.combine(directory, item)

        if path ~= "rom" then
            if fs.isDir(path) then
                count = count + cosUtils.fileCount(path)
            else
                count = count + 1
            end
        end
    end

    return count
end

function cosUtils.isMonitorHere()
    local monitor = peripheral.find("monitor")

    if monitor then
        return monitor
    else
        return nil
    end
end

function cosUtils.monSlowPrint(txt, delay)
    local monitor = cosUtils.isMonitorHere()
    if not monitor then return assert("Monitor not found") end

    if not delay then
        delay = 0.3
    end

    for i = 1, #txt do
        monitor.write(txt:sub(i, i))
        os.sleep(delay)
    end
end

function cosUtils.menuKeyUpDownManagement(key, num, max, min)
    if key == keys.up then
        num = num == min and max or num - 1
    elseif key == keys.down then
        num = num == max and min or num + 1
    end

    return num
end

function cosUtils.del(name, dir)
    if not dir then
        -- get the size of the file
        local size = fs.getSize(name)
        local timeTodelete = size / 1000
        textutils.slowPrint("Removing file: " .. name .. "...")
        os.sleep(timeTodelete)
        shell.run("delete", tostring(name))
        print("File: %n, deleted", name)

        return
    end

    textutils.slowPrint("Removing Directory: " .. name .. "...")
    -- Size of the directory
    local size = fs.getSize(name)
    local timeTodelete = size / 1000
    os.sleep(timeTodelete)
    shell.run("delete", tostring(name))
    print("Directory: %n, deleted", name)
end

function cosUtils.drawBox(win, x, y, width, height, fgColor, bgColor)
    fgColor = fgColor or colors.white
    bgColor = bgColor or colors.black
    -- Draw the top-left corner & top border.
    win.setBackgroundColor(bgColor)
    win.setTextColor(fgColor)
    win.setCursorPos(x - 1, y - 1)
    win.write("\x9C" .. ("\x8C"):rep(width))
    -- Draw the top-right corner.
    win.setBackgroundColor(fgColor)
    win.setTextColor(bgColor)
    win.write("\x93")

    -- Draw the right border.
    for i = 1, height do
        win.setCursorPos(win.getCursorPos() - 1, y + i - 1)
        win.write("\x95")
    end

    -- Draw the left border.
    win.setBackgroundColor(bgColor)
    win.setTextColor(fgColor)

    for i = 1, height do
        win.setCursorPos(x - 1, y + i - 1)
        win.write("\x95")
    end

    -- Draw the bottom border and corners.
    win.setCursorPos(x - 1, y + height)
    win.write("\x8D" .. ("\x8C"):rep(width) .. "\x8E")
end

function cosUtils.getTime(timeFormat, hourMinOnly)
    -- Default values
    hourMinOnly = hourMinOnly or false
    timeFormat = timeFormat or settings.get("timeFormat")

    -- Validate timeFormat input
    if timeFormat ~= "12" and timeFormat ~= "24" then
        timeFormat = "12" -- default to 12-hour format if invalid
    end

    local tostr = tostring
    local strlen = string.len
    local date = os.date("*t")
    -- Extract date and time components
    local year = tostr(date.year)
    local month = tostr(date.month)
    local day = tostr(date.day)
    local hour = tostr(date.hour)
    local min = tostr(date.min)
    local sec = tostr(date.sec)
    local ampm = " "

    -- Handle 12-hour format
    if timeFormat == "12" then
        ampm = date.hour >= 12 and "PM" or "AM"
        hour = date.hour % 12
        hour = (hour == 0) and 12 or hour -- handle midnight case
    end

    -- Format components to ensure two-digit format
    local function padWithZero(value)
        return strlen(value) == 1 and "0" .. value or value
    end

    month = padWithZero(month)
    day = padWithZero(day)
    hour = padWithZero(hour)
    min = padWithZero(min)
    sec = padWithZero(sec)
    -- Return the formatted time
    if hourMinOnly then return hour, min, ampm end
    local dateFormat = year .. "-" .. month .. "-" .. day
    local timeFormatt = hour .. ":" .. min .. ":" .. sec

    return dateFormat .. " " .. timeFormatt .. " " .. ampm
end

function cosUtils.readFile(path)
    local file, err = fs.open(path, "r")
    if not file then return nil, err end
    local content = file.readAll()
    file.close()

    return content
end

function cosUtils.logToOS(msg)
    local logFileName = "os/data/OS.log"
    local mode = fs.exists(logFileName) and "a" or "w"
    local time = "[" .. cosUtils.getTime() .. "]"
    local size = fs.getSize(logFileName)

    local file = fs.open(logFileName, mode)
    file.write(msg .. " " .. time .. "\n")
    file.close()

    if size >= 50000 then
        file = fs.open(logFileName, "w")
        file.write(" ")
        file.close()
        file = fs.open(logFileName, "a")
        file.write("\n[A:22] Logs reached 50,000 bytes. Deleting logs at " .. cosUtils.getTime())
        file.close()
    end
end

function cosUtils.resetScreen(win)
    win.clear()
    win.setCursorPos(1, 1)
    win.setBackgroundColor(colors.black)
    win.setTextColor(colors.white)
end

function cosUtils.goodByeSetup(device)
    local w, h = device.getSize()
    local x = math.floor((w - string.len("Goodbye")) / 2)
    local y = math.floor(h / 2)
    cosUtils.resetScreen(device)
    device.setCursorPos(x, y)
end

function cosUtils.centerPrint(yPos, w, text, col, win)
    win = win or term
    col = col and col or colors.black
    local xPos = math.floor((w - string.len(text)) / 2)
    win.setBackgroundColor(col)
    win.setCursorPos(xPos, yPos)
    --term.setBackgroundColor(col)
    --term.clearLine()
    win.write(text)
end


function cosUtils.centerPrintTable(y, w, items, numOp, slowPrint, backgroundColor, boxmargins, window, textColors)
    textColors = textColors or {}
    window = window or term

    backgroundColor = backgroundColor and backgroundColor or colors.black
    slowPrint = slowPrint == nil and false or slowPrint
    numOp = numOp or 0
    boxmargins = boxmargins == nil and true or boxmargins
    -- Calculate the longest line
    local longestLine = 0

    for _, item in ipairs(items) do
        if #item > longestLine then
            longestLine = #item
        end
    end

    -- Set Box Dimensions
    local wMarg, hMarg = boxmargins and 4 or 0, boxmargins and 2 or 0
    local boxWidth = longestLine + wMarg -- 1 margin on each side + 2 for borders
    local boxHeight = #items + hMarg -- 1 margin on top and bottom + 2 for borders
    -- Calculate the starting position
    local x = math.floor((w - boxWidth) / 2)
    local yStart = y
    -- Draw the box around the menu
    cosUtils.drawBox(window, x, yStart, boxWidth, boxHeight)

    -- Print the menu items inside the box
    for i, item in ipairs(items) do
        local text = item
        local xPos = math.floor((w - #text) / 2)
        yStart = boxmargins and yStart or yStart - 1
        window.setCursorPos(xPos, yStart + i)
        window.setBackgroundColor(backgroundColor)
        window.setTextColor(textColors[i] or colors.white)

        if slowPrint then
            textutils.slowWrite(text, 9)
        else
            window.write(text)
        end
    end

    window.setBackgroundColor(colors.black)
    window.setTextColor(colors.white)
end

function cosUtils.centerPrintTableTest(y, w, items, numOp, slowPrint, backgroundColor, boxmargins, window)
    window = window or term
    backgroundColor = backgroundColor or colors.black
    slowPrint = slowPrint == nil and false or slowPrint
    numOp = numOp or 0
    boxmargins = boxmargins == nil and true or boxmargins
    -- Calculate the longest line
    local longestLine = 0

    for _, item in ipairs(items) do
        if #item.text > longestLine then
            longestLine = #item.text
        end
    end

    -- Set Box Dimensions
    local wMarg, hMarg = boxmargins and 4 or 0, boxmargins and 2 or 0
    local boxWidth = longestLine + wMarg
    local boxHeight = #items + hMarg
    -- Calculate the starting position
    local x = math.floor((w - boxWidth) / 2)
    local yStart = y
    -- Draw the box around the menu
    cosUtils.drawBox(window, x, yStart, boxWidth, boxHeight)

    -- Print the menu items inside the box
    for i, item in ipairs(items) do
        local text = item.text
        local xPos = math.floor((w - #text) / 2)
        yStart = boxmargins and yStart or yStart - 1
        window.setCursorPos(xPos, yStart + i)
        window.setBackgroundColor(backgroundColor)
        -- Determine if fail conditions are met
        local fail = false

        for _, condition in ipairs(item.failConditions or {}) do
            if load("return " .. condition)() then
                fail = true
                break
            end
        end

        -- Set text color based on fail conditions
        if fail then
            window.setTextColor(item.failColor or colors.red)
        else
            window.setTextColor(item.defaultColor or colors.white)
        end

        -- Print the text
        if slowPrint then
            textutils.slowWrite(text, 9)
        else
            window.write(text)
        end
    end

    window.setBackgroundColor(colors.black)
    window.setTextColor(colors.white)
end

function cosUtils.error(device, er)
    local _, curY = device.getCursorPos()
    device.setCursorPos(1, curY + 1)
    error(er, 1)
end

function cosUtils.findFile(filename, directory)
    directory = directory or "/" -- Set the default directory to the root if none is provided

    -- List all items in the current directory
    for _, item in ipairs(fs.list(directory)) do
        local path = fs.combine(directory, item)

        -- Check if the item is a directory
        if fs.isDir(path) then
            -- Recursively search within the directory
            local result = cosUtils.findFile(filename, path)
            -- If the file is found, return the path relative to the current directory
            if result then return "/" .. fs.combine(item, result) end
        elseif item == filename then
            return "/" .. fs.combine("", filename)
        end
        -- If the item matches the filename, return the full path
    end
end

function cosUtils.loadingBar(device, y, col)
    local w, _ = device.getSize()
    local length = 10 -- Fixed length of the loading bar
    local x = math.floor((w - length) / 2) -- Center the bar on the screen
    y = y - 1
    local fileCount = cosUtils.fileCount("")
    local totalTime = fileCount * 0.075
    local timePerChar = totalTime / length
    cosUtils.drawBox(device, x, y, length, 1) -- Draw the box around the bar
    device.setBackgroundColor(col)
    device.setTextColor(colors.white)

    -- Start with a fully filled bar
    for j = 1, length do
        device.setCursorPos(x + j - 1, y)
        device.write("\x7f") -- Initially filled with block characters
    end

    -- Custom slowprint with percentage and time remaining update
    local startTime = os.epoch("utc") -- More precise time measurement

    for i = 1, length do
        device.setBackgroundColor(col)
        device.setTextColor(colors.white)
        -- Replace block character with a space
        device.setCursorPos(x + i - 1, y)
        device.write(" ")
        -- Calculate and display percentage
        local percentage = math.floor((i / length) * 100)
        device.setCursorPos((w / 2) - string.len(percentage / 2), y) -- Move cursor to the percentage position
        device.write(percentage .. "%")
        device.setBackgroundColor(colors.black)
        device.setTextColor(colors.white)

        if developmentMode then
            -- Calculate and display time remaining
            local currentTime = os.epoch("utc")
            local elapsedTime = (currentTime - startTime) / 1000 -- Elapsed time in seconds
            local remainingTime = totalTime - elapsedTime -- Remaining time based on total time
            device.setCursorPos(x - 1, y + 2)
            device.write(string.format("%.2fs", remainingTime))
        end

        os.sleep(timePerChar) -- Slowprint delay
    end

    if developmentMode then
        -- Ensure the display shows 0s at the end
        device.setCursorPos(x - 1, y + 2)
        device.write("0.00s")
    end

    -- Reset colors after completion
    device.setBackgroundColor(colors.black)
    device.setTextColor(colors.white)
end

function cosUtils.convertToSeconds(previous, current)
    local difference = current - previous
    local secondsPassed = difference / 0.01

    return string.format("%.3f", secondsPassed)
end

function cosUtils.BSOD(err, device)
    cosUtils.resetScreen(device)
    device.setBackgroundColor(colors.blue)
    device.setTextColor(colors.white)
    -- Replace the spaces with underscores, and capitalize the text
    err = string.upper(string.gsub(err, " ", "_"))
    local x, y = device.getSize()

    -- Write " " across the whole screen
    for i = 1, y do
        device.setCursorPos(1, i)
        device.write(string.rep(" ", 51))
    end

    for i = 1, x do
        device.setCursorPos(i, 1)
        device.write(" ")
    end

    local errCodes = RMA() .. " (" .. RMA() .. ", " .. RMA() .. ", " .. RMA() .. ", " .. RMA() .. ")"
    term.setCursorPos(1, 1)
    print("A problem has been detected and CookieOS has been shut down to prevent damage to your computer\n")
    print(err)
    print("\nIf this is the first time you've seen this error screen, restart your computer. If this screen appears again please contact princeofcookies on Discord\n")
    print("Technical information:\n")
    print("**STOP: " .. errCodes)
    device.setCursorPos(1, y)
    device.write("Press any key to continue...")
    local event = os.pullEvent("key")

    if event == "key" then
        cosUtils.logToOS("[BSOD] " .. err .. " | " .. errCodes)
        cosUtils.goodByeSetup(device)
        os.reboot()
    end
end

function cosUtils.getFPS()
    local startTime = os.epoch("utc")
    local endTime = startTime + 10  -- Measure over 10 milliseconds
    local frames = 0

    while os.epoch("utc") < endTime do
        frames = frames + 1
    end

    local actualTimePassed = os.epoch("utc") - startTime
    local fps = (frames / actualTimePassed) * 1000  -- Convert to frames per second

    return math.floor(fps)
end

function cosUtils.waterMark(win)
    win = win or term
    cosUtils.resetScreen(win)
    win.setTextColor(colors.yellow)
    win.write(cosv)
    win.setCursorPos(1, 2)
    win.setTextColor(colors.green)
    win.write("FPS: " .. cosUtils.getFPS())
    win.setTextColor(colors.white)
end

function cosUtils.safeRun(func, ...)
    local status, err = pcall(func, ...)

    if not status then
        cosUtils.BSOD(err, term)
    end

    return status, err
end

function cosUtils.drawMenu(device)
    drawMenuWin.setVisible(false)
    drawMenuWin.clear()
    -- device = device or term
    local rw, _ = drawMenuWin.getSize()
    local hour, minute, ampm = cosUtils.getTime("12", true)
    drawMenuWin.setCursorPos(1, 1)
    drawMenuWin.setTextColor(colors.yellow)
    drawMenuWin.write(cosv)
    drawMenuWin.setTextColor(colors.white)
    drawMenuWin.setCursorPos(rw - string.len(hour .. ":" .. minute .. " " .. ampm), 1)
    drawMenuWin.write(hour .. ":" .. minute .. " " .. ampm)
    drawMenuWin.setCursorPos(1, 2)
    drawMenuWin.setTextColor(colors.green)
    drawMenuWin.write("FPS: " .. cosUtils.getFPS())
    drawMenuWin.setVisible(true)
end

function cosUtils.isModemHere()
    local modem = peripheral.find("modem")
    if modem == nil or not modem then return false end

    for k, v in pairs(modem) do
        if k == "transmit" then return true, modem end
    end
end

function cosUtils.textFlash(x, y, text, delay)
    if not delay then
        delay = 0.3
    end

    local monitor = cosUtils.isMonitorHere()

    if monitor then
        -- Loop the text flashing
        while true do
            monitor.setCursorPos(x, y)
            monitor.write(text)
            os.sleep(delay)
            monitor.setCursorPos(x, y)
            monitor.clearLine()
            os.sleep(delay)
        end
    else
        while true do
            term.setCursorPos(x, y)
            term.write(text)
            os.sleep(delay)
            term.setCursorPos(x, y)
            term.clearLine()
            os.sleep(delay)
        end
    end
end

function cosUtils.onScreenKeyboard()
    local monitor = cosUtils.isMonitorHere()
    if not monitor then return assert("Monitor not found") end
    local _, h = monitor.getSize()

    local keyboard = {
        {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "bksp"},
        {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p"},
        {"a", "s", "d", "f", "g", "h", "j", "k", "l", "enter"},
        {"shift", "z", "x", "c", "v", "b", "n", "m"},
        {"space"}
    }

    monitor.clear()
    monitor.setBackgroundColor(colors.black)
    local totalWidth = 0

    for i = 1, #keyboard[1] do
        totalWidth = totalWidth + string.len(keyboard[1][i]) + 2
    end

    local startX = math.floor((w - totalWidth) / 2)
    local startY = h - (#keyboard * 2)

    local function drawKeyboard()
        for i = 1, #keyboard do
            local lineWidth = 0

            for j = 1, #keyboard[i] do
                lineWidth = lineWidth + string.len(keyboard[i][j]) + 2
            end

            local keyStartX = startX + math.floor((totalWidth - lineWidth) / 2)

            for j = 1, #keyboard[i] do
                local key = keyboard[i][j]
                local keyWidth = string.len(key) + 2
                local keyX = keyStartX
                local keyY = startY + (2 * (i - 1))

                local colorss = {colors.white, colors.orange, colors.magenta, colors.lightBlue, colors.yellow, colors.lime, colors.pink, colors.gray, colors.lightGray, colors.cyan, colors.purple, colors.blue, colors.brown, colors.green, colors.red}

                local color1 = colorss[math.random(1, #colorss)]
                local color2 = colorss[math.random(1, #colorss)]

                while color2 == color1 do
                    color2 = colorss[math.random(1, #colorss)]
                end

                monitor.setTextColor(color1)
                monitor.setBackgroundColor(color2)
                monitor.setCursorPos(keyX, keyY)
                monitor.write(string.rep(" ", keyWidth))
                monitor.setCursorPos(keyX + 1, keyY)
                monitor.write(key)
                keyStartX = keyStartX + keyWidth
            end
        end
    end

    local function drawCursor(x, y)
        monitor.setCursorPos(x, y)
        monitor.write("_")
    end

    -- local function removeCursor(x, y)
    --     monitor.setCursorPos(x, y)
    --     monitor.write(" ")
    -- end

    local function drawText(x, y, text)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(x, y)
        monitor.write(text)
    end

    -- local function removeText(x, y, text)
    --     monitor.setCursorPos(x, y)
    --     monitor.write(string.rep(" ", string.len(text)))
    -- end

    local function changeKeyboardCase(toUpperCase)
        for i = 1, #keyboard do
            for j = 1, #keyboard[i] do
                if toUpperCase then
                    keyboard[i][j] = string.upper(keyboard[i][j])
                else
                    keyboard[i][j] = string.lower(keyboard[i][j])
                end
            end
        end
    end

    local cursorX = 3
    local cursorY = 1
    monitor.setCursorPos(1, 1)
    monitor.write(">")
    drawCursor(cursorX, cursorY)
    drawKeyboard()
    local shiftDown = false

    while true do
        local _, _, x, y = os.pullEvent("monitor_touch")

        if x >= startX and x <= startX + totalWidth and y >= startY and y <= h then
            local relativeX = x - startX
            local keyX, keyY
            local currentWidth = 0

            for i = 1, #keyboard do
                for j = 1, #keyboard[i] do
                    currentWidth = currentWidth + string.len(keyboard[i][j]) + 2

                    if relativeX <= currentWidth then
                        keyX = j
                        keyY = i
                        break
                    end
                end

                if keyX then break end
            end

            if keyY == 5 then
                drawText(cursorX, cursorY, " ")
                cursorX = cursorX + 1
                drawCursor(cursorX, cursorY)
            else
                local key = keyboard[keyY][keyX]

                if string.lower(key) == "bksp" then
                    drawText(cursorX, cursorY, " ")
                    cursorX = cursorX - 1
                    drawCursor(cursorX, cursorY)
                elseif string.lower(key) == "enter" then
                    break
                elseif string.lower(key) == "shift" then
                    shiftDown = not shiftDown
                    changeKeyboardCase(shiftDown)
                    drawKeyboard()
                else
                    drawText(cursorX, cursorY, key)
                    cursorX = cursorX + 1
                    drawCursor(cursorX, cursorY)
                end
            end
        end
    end
end

function cosUtils.getSizeOfCosUtils()
    funcCount = 0
    for k, v in pairs(cosUtils) do
        if type(v) == "function" then
            funcCount = funcCount + 1
        end
    end

    return funcCount
end




return cosUtils