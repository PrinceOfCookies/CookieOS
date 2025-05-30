local chat = peripheral.find("chatBox")

if not chat then
    error("Chat peripheral not found. Please ensure it is connected and try again.")
end

local players = {}

local function sendChatMessage(message)
    if type(message) ~= "string" or message == "" then
        error("Invalid message. Please provide a non-empty string.")
    end

    chat.sendMessage(message, "Davey", "<>")
end

local function receiveChatMessage()
    local event, message, sender
    while true do
        event, username, message, _, _ = os.pullEvent("chat")
        if event == "chat" then
            print("[" .. sender .. "]: " .. message)

            if not players[sender] then
                players[sender] = {}
                print("New player detected: " .. sender)
            end

            table.insert(players[sender], {time = os.clock(), message = message})

            -- Sort the table, newest time on top
            table.sort(players[sender], function(a, b)
                return a.time > b.time
            end)
            

            if string.StartsWith(message, ".,") then
                -- Send the message to the ChatGPT API
                local query = string.sub(message, 3) -- Remove the prefix ".,"
                if query and query ~= "" then
                    local response = cosUtils.chatGPT(query)
                    if response then
                        sendChatMessage(response)
                    else
                        print("Error: No response from ChatGPT.")
                    end
                else
                    print("Error: Empty query.")
                end
            end
        end
    end
end