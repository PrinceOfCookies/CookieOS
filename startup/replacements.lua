-- SPDX-FileCopyrightText: 2017 Daniel Ratcliffe
--
-- SPDX-License-Identifier: LicenseRef-CCPL

local completion = require "cc.shell.completion"
local lastDirFile = "os/data/lastDir.txt"
local replacementPath = "/programReplacements"
local originalSetDir = shell.setDir
local originalResolveProgram = shell.resolveProgram
local originalOSV = os.version
local originalreboot = os.reboot
local originalShutdown = os.shutdown
colors.grey = colors.gray

local function readLastDir()
    if fs.exists(lastDirFile) then
        local file = fs.open(lastDirFile, "r")
        local lastDir = file.readLine()
        file.close()

        return lastDir
    end

    return shell.dir()
end

local function writeLastDir(dir)
    local file = fs.open(lastDirFile, "w")
    file.write(dir)
    file.close()
end

local function getDirectorySize(sPath)
    local totalSize = 0
    local tList = fs.list(sPath)

    for _, sItem in pairs(tList) do
        local sItemPath = fs.combine(sPath, sItem)

        if fs.isDir(sItemPath) then
            totalSize = totalSize + getDirectorySize(sItemPath)
        else
            totalSize = totalSize + fs.getSize(sItemPath)
        end
    end

    return totalSize
end

local function formatSize(size)
    size = tonumber(size)

    if size >= 1024 * 1024 then
        return string.format("%.2f MB", size / (1024 * 1024))
    elseif size >= 1024 then
        return string.format("%.2f KB", size / 1024)
    else
        return string.format("%d B", size)
    end
end

local function betterModified(modified, hdOnly)
    hdOnly = hdOnly or false
    local cur = os.epoch("utc")
    local diff = cur - modified
    local seconds = math.floor(diff / 1000)
    local minutes = math.floor(seconds / 60)
    local hours = math.floor(minutes / 60)
    local days = math.floor(hours / 24)
    local weeks = math.floor(days / 7)
    local months = math.floor(days / 30)
    local years = math.floor(days / 365)
    seconds = seconds % 60
    minutes = minutes % 60
    hours = hours % 24
    days = days % 7
    weeks = weeks % 4
    months = months % 12
    local Time = ""

    if hdOnly then
        if days > 0 then
            Time = Time .. days .. " days"
            if hours > 0 then
                Time = Time .. ", " .. hours .. " hrs"
            end
        elseif hours > 0 then
            Time = Time .. hours .. " hrs"
            if minutes > 0 then
                Time = Time .. ", " .. minutes .. " mins"
            end
        elseif minutes > 0 then
            Time = Time .. minutes .. " mins, " .. seconds .. " secs"
        else
            Time = Time .. seconds .. " secs"
        end
    else
        if years > 0 then
            Time = Time .. years .. " years, "
        end

        if months > 0 then
            Time = Time .. months .. " months, "
        end

        if weeks > 0 then
            Time = Time .. weeks .. " weeks, "
        end

        if days > 0 then
            Time = Time .. days .. " days, "
        end

        if hours > 0 then
            Time = Time .. hours .. " hrs, "
        end

        if minutes > 0 then
            Time = Time .. minutes .. " mins, "
        end

        Time = Time .. seconds .. " secs"
    end

    return Time
end

local function findMostRecentModifiedInDirectory(directory)
    if not fs.exists(directory) then return nil end
    local files = fs.list(directory)
    local mostRecent = nil
    local mostRecentTime = 0

    for _, file in pairs(files) do
        if fs.isDir(file) then
            local time = findMostRecentModifiedInDirectory(fs.combine(directory, file))

            if time > mostRecentTime then
                mostRecentTime = time
                mostRecent = file
            end
        else
            local time = fs.attributes(fs.combine(directory, file)).modified

            if time > mostRecentTime then
                mostRecentTime = time
                mostRecent = file
            end
        end
    end

    return mostRecentTime
end

fs.attributes2 = function(path, hdOnly)
    hdOnly = hdOnly or false

    if not fs.exists(path) then
        path = fs.combine(shell.dir(), path)
    end

    local attributes = fs.attributes(path)

    attributes.size = formatSize(fs.isDir(path) and getDirectorySize(path) or fs.getSize(path))
    attributes.modified = betterModified(fs.isDir(path) and findMostRecentModifiedInDirectory(path) or attributes.modified, hdOnly)
    attributes.created = betterModified(attributes.created, hdOnly)

    return attributes
end

shell.resolveProgram = function(command)
    -- Check if the command exists in the programReplacements directory
    local sReplacementPath = fs.combine(replacementPath, command)

    if fs.exists(sReplacementPath) and not fs.isDir(sReplacementPath) then
        return sReplacementPath
    else
        local sReplacementPathLua = sReplacementPath .. ".lua"
        if fs.exists(sReplacementPathLua) and not fs.isDir(sReplacementPathLua) then return sReplacementPathLua end
    end

    return originalResolveProgram(command)
end

shell.setDir = function(newDir, logLastdir)
    logLastdir = logLastdir or true
    local lastDir = shell.dir()

    if lastDir == "" then
        lastDir = "/"
    end

    if logLastdir then
        writeLastDir(lastDir)
    end

    return originalSetDir(newDir)
end

os.version = function()
    return originalOSV(),  cosv
end

shell.lastDir = function()
    local lastDir = readLastDir()
    shell.run("cd " .. lastDir)
end

os.reboot = function()
    cosUtils.goodByeSetup(term)

    if term.isColor() then
        term.setTextColor(colors.yellow)
    end

    print("Goodbye")

    term.setTextColor(colors.white)
    sleep(1)
    return originalreboot()
end

os.shutdown = function()
    cosUtils.goodByeSetup(term)

    if term.isColor() then
        term.setTextColor(colors.yellow)
    end

    print("Goodbye")

    term.setTextColor(colors.white)
    sleep(1)
    return originalShutdown()
end



-- Set completion function for list to completion dir, or one of the opens -i - h or -s
shell.setCompletionFunction("programReplacements/list.lua", completion.build(completion.dir))
shell.setCompletionFunction("programReplacements/ls.lua", completion.build(completion.dir))