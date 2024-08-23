-- SPDX-FileCopyrightText: 2017 Daniel Ratcliffe
--
-- SPDX-License-Identifier: LicenseRef-CCPL
local tArgs = {...}

-- Helper function to display items in columns
local function displayHorizontally(items, margin)
    local screenWidth, _ = term.getSize()
    local margin = margin or 4
    local maxWidth = screenWidth - margin
    local line = ""

    for _, item in ipairs(items) do
        if #line + #item + margin > maxWidth then
            print(line)
            line = item
        else
            if #line > 0 then
                line = line .. string.rep(" ", margin) .. item
            else
                line = item
            end
        end
    end

    if #line > 0 then
        print(line)
    end
end

local sDir = shell.dir()

if tArgs[1] ~= nil then
    sDir = shell.resolve(tArgs[1])
end

if not fs.isDir(sDir) then
    if tArgs[1] == "-s" then
        -- Just get the size of ALL of the files
        local totalSize = 0
        local tList = fs.list("")

        for _, sItem in pairs(tList) do
            local sItemPath = fs.combine("", sItem)

            if fs.isDir(sItemPath) then
                totalSize = totalSize + utils.getDirectorySize(sItemPath)
            else
                totalSize = totalSize + fs.getSize(sItemPath)
            end
        end

        print("Total size: " .. utils.formatSize(totalSize))
    elseif tArgs[1] == "-i" then
        -- Display the attributes of the directory
        local tAttributes = fs.attributes2("")
        print("Attributes of /")
        print(textutils.serialize(tAttributes))

        return
    elseif tArgs[1] == "-h" then
        print("Usage: list [-s] [-i] [-h] [directory], list <directory> [-i]")
        print("  -s: Display the total size of all files in the current directory")
        print("  <directory> -i: Display the attributes of the directory")
        print("  -h: Display this help message")
    else
        printError("Not a directory")
    end

    return
end

if tArgs[2] == "-i" then
    -- Displa the attributes of the directory
    local tAttributes = fs.attributes2(sDir)
    print("Attributes of " .. sDir)
    print(textutils.serialize(tAttributes))
end

if not tArgs[2] then
    local tFiles, tDirs = utils.getFilesAndDirs(sDir)

    if term.isColour() then
        term.setTextColor(colors.green)
        displayHorizontally(tDirs, 4)
        term.setTextColor(colors.white)
        displayHorizontally(tFiles, 4)
    else
        term.setTextColor(colors.lightGray)
        displayHorizontally(tDirs, 4)
        term.setTextColor(colors.white)
        displayHorizontally(tFiles, 4)
    end
end