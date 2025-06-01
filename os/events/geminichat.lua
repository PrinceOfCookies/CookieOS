-- !TODO MAKE THIS RUN IN COROUTINE SO THAT OTHER EVENTS CAN BE HANDLED
local chat = peripheral.find("chatBox")
if not chat then
    if term and term.setTextColor then
        local oldColor = term.getTextColor()
        term.setTextColor(colors.red)
        print("Chat peripheral not found. Please ensure it is connected and try again.")
        term.setTextColor(oldColor)
    else
        print("ERROR: Chat peripheral not found. Please ensure it is connected and try again.")
    end
    return
end

local players = {}
local function printError(msg)
    if term and term.setTextColor then
        local oldColor = term.getTextColor()
        term.setTextColor(colors.red)
        print(msg)
        term.setTextColor(oldColor)
    else
        print("ERROR: " .. msg)
    end
end

if not cosUtils or not cosUtils.Gemini then
    printError("CRITICAL: cosUtils.Gemini function is not defined!")
    printError("Please ensure the Gemini API function is included in this script or required correctly.")
end

local function sendChatMessage(message)
    if type(message) ~= "string" or message == "" then
        printError("Invalid message to send. Please provide a non-empty string.")
        return
    end

    chat.sendMessage(message, "Davey", "<>")
end

local function getHistory()
    local history_lines = {} -- This will be the final flat list of formatted messages
    for playerName, playerMessageList in pairs(players) do
        local num_messages_to_take = math.min(10, #playerMessageList)
        local displayName = playerName
        if playerName == "gem" then displayName = "Davey" end
        for i = num_messages_to_take, 1, -1 do
            local message_object = playerMessageList[i]
            table.insert(history_lines, displayName .. ": " .. message_object.message)
        end
    end
    return history_lines
end

local function receiveChatMessage()
    local event, sender, message
    print("Chat monitor started. Listening for messages...")
    print("Type '.,<your query>' to ask Davey (using Gemini).")
    while true do
        event, sender, message = os.pullEvent("chat")
        if event == "chat" and sender and message then
            print("[" .. sender .. "]: " .. message)
            if not players[sender] then
                players[sender] = {}
                print("New player detected: " .. sender)
            end

            table.insert(players[sender], {
                time = os.clock(),
                message = message
            })

            table.sort(players[sender], function(a, b) return a.time > b.time end)
            if string.sub(message, 1, 2) == ".," then
                local query = string.sub(message, 3)
                if query and query:match("%S") then
                    query = query:match("^%s*(.-)%s*$")
                    print("Sending query to Gemini: '" .. query .. "'")
                    local response, err = cosUtils.Gemini(query, getHistory())
                    if response then
                        print("Gemini response: " .. response)
                        cosUtils.logToOS(playerName .. " asked: " .. query)
                        sendChatMessage(response)
                        cosUtils.logToOS("Gemini response: " .. response)

                        players["gem"] = players["gem"] or {}
                        table.insert(players["gem"], {
                            time = os.clock(),
                            message = response
                        })

                        local tableSize = textutils.serialize(players):len()
                        print("Players table size: " .. tableSize .. " bytes")
                    else
                        local errorMsg = err or "No response or unknown error from Gemini."
                        printError("Error processing Gemini query: " .. errorMsg)
                    end
                else
                    printError("Error: Empty query after prefix.")
                end
            elseif message == "!tblsize" then
                local tableSize = textutils.serialize(players):len()
                sendChatMessage("Players table size: " .. tableSize .. " bytes")
                local sizes = {}
                for player, messages in pairs(players) do
                    sizes[player] = textutils.serialize(messages):len()
                end

                for player, size in pairs(sizes) do
                    sendChatMessage(player .. " table size: " .. size .. " bytes")
                    os.sleep(0.2)
                end

                sendChatMessage("Gemini table size: " .. textutils.serialize(players["gem"] or {}):len() .. " bytes")
            end
        end

        os.sleep(0.1)
    end
end

receiveChatMessage()