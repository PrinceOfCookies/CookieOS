local eventTrackerPath = "os/events"
local function printError(msg)
    if cosUtils and cosUtils.error then
        cosUtils.error(term, msg)
    else
        print("ERROR: " .. msg)
    end
end

if not fs.exists(eventTrackerPath) then
    printError("Path does not exist: " .. eventTrackerPath)
else
    local files = fs.list(eventTrackerPath)
    for _, file in ipairs(files) do
        local filePath = fs.combine(eventTrackerPath, file)
        if fs.isDir(filePath) then
            printError("Skipping directory: " .. filePath)
        elseif not string.match(file, "%.lua$") then
            printError("Skipping non-Lua file: " .. filePath)
        else
            local success, err = pcall(function()
                local chunk, loadErr = loadfile(filePath) -- Load file as a function chunk
                if chunk then
                    local eventFunc = chunk() -- Execute chunk to get returned function
                    if type(eventFunc) == "function" then
                        -- Create a multishell
                        cosUtils.logToOS("Starting event handler from file: " .. filePath)
                        local shell = multishell.launch(term.current(), filePath, coroutine.wrap(eventFunc)()) -- Run function in coroutine
                        shell:setTitle(file) -- Set the title of the shell
                    else
                        printError("File " .. file .. " did not return a function.")
                    end
                else
                    printError("Error loading file " .. file .. ": " .. loadErr)
                end
            end)

            if not success then printError("Runtime error in file " .. file .. ": " .. err) end
        end
    end
end