-- SPDX-FileCopyrightText: 2017 Daniel Ratcliffe
--
-- SPDX-License-Identifier: LicenseRef-CCPL
local tArgs = {...}

-- Directory for program replacements
local replacementsDir = "/programReplacements"
-- Load or define aliases
local tAliases = {}

-- Function to load aliases from the replacements directory
local function loadAliases()
    if fs.exists(replacementsDir) and fs.isDir(replacementsDir) then
        local tDirs = fs.list(replacementsDir)

        for _, folder in ipairs(tDirs) do
            local folderPath = fs.combine(replacementsDir, folder)

            if fs.isDir(folderPath) then
                local tAliasesInFolder = fs.list(folderPath)

                for _, aliasFile in ipairs(tAliasesInFolder) do
                    local aliasPath = fs.combine(folderPath, aliasFile)

                    if not fs.isDir(aliasPath) then
                        -- Strip the ".lua" extension if present
                        local aliasName = string.match(aliasFile, "^(.-)%.lua$")

                        if aliasName then
                            tAliases[aliasName] = aliasPath
                        end
                    end
                end
            end
        end
    end
end

-- Helper function to check and resolve aliases
local function resolveAlias(command)
    if tAliases[command] then return tAliases[command] end

    return command
end

-- Helper function to calculate the size of a directory
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

-- Helper function to format the size
local function formatSize(size)
    if size >= 1024 * 1024 then
        return string.format("%.2f MB", size / (1024 * 1024))
    elseif size >= 1024 then
        return string.format("%.2f KB", size / 1024)
    else
        return string.format("%d B", size)
    end
end

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

-- Load aliases from the replacements directory
loadAliases()
-- Resolve the directory path considering aliases
local sDir = shell.dir()

if tArgs[1] ~= nil then
    sDir = shell.resolve(tArgs[1])
end

-- Resolve any aliases in the directory path
sDir = resolveAlias(sDir)

local function getFilesAndDirs(sDir)
    -- Sort into dirs/files, and calculate column count
    local tAll = fs.list(sDir)
    local tFiles = {}
    local tDirs = {}
    local bShowHidden = settings.get("list.show_hidden")

    for _, sItem in pairs(tAll) do
        if bShowHidden or string.sub(sItem, 1, 1) ~= "." then
            local sPath = fs.combine(sDir, sItem)

            if fs.isDir(sPath) then
                local dirSize = getDirectorySize(sPath)
                local readOnly = fs.isReadOnly(sPath)
                local prefix = readOnly and "\xB7" or ""
                table.insert(tDirs, prefix .. sItem .. prefix .. " (" .. formatSize(dirSize) .. ")")
            else
                local fileSize = fs.getSize(sPath)
                local readOnly = fs.isReadOnly(sPath)
                local prefix = readOnly and "\xB7" or ""
                table.insert(tFiles, prefix .. sItem .. prefix .. " (" .. formatSize(fileSize) .. ")")
            end
        end
    end

    return tFiles, tDirs
end

if not fs.isDir(sDir) then
    if tArgs[1] == "-s" then
        -- Just get the size of ALL of the files
        local totalSize = 0
        local tList = fs.list("")

        for _, sItem in pairs(tList) do
            local sItemPath = fs.combine("", sItem)

            if fs.isDir(sItemPath) then
                totalSize = totalSize + getDirectorySize(sItemPath)
            else
                totalSize = totalSize + fs.getSize(sItemPath)
            end
        end

        print("Total size: " .. formatSize(totalSize))
    elseif tArgs[1] == "-i" then
        -- Display the attributes of the directory
        local tAttributes = fs.attributes2("")
        -- local size = getDirectorySize("")
        -- local modified = betterModified(tAttributes.modified)
        -- local created = betterModified(tAttributes.created)
        -- tAttributes.size = size
        -- tAttributes.modified = modified
        -- tAttributes.created = created
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
    -- local size = getDirectorySize(sDir)
    -- local modified = betterModified(tAttributes.modified)
    -- local created = betterModified(tAttributes.created)
    -- tAttributes.size = size
    -- tAttributes.modified = modified
    -- tAttributes.created = created
    print("Attributes of " .. sDir)
    print(textutils.serialize(tAttributes))
end

if not tArgs[2] then
    local tFiles, tDirs = getFilesAndDirs(sDir)

    -- Display directories and files horizontally
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