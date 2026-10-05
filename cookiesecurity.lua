local choices = {
    { "CraftOS shell", function() shell.run("shell") end },
    { "Speaker music player", function() shell.run("/os/programs/PlayMusic") end },
    { "Edit node configuration", function() shell.run("edit", "/cookieos-node.lua") end },
    { "Pair this node", function() shell.run("/pair-node.lua") end },
    { "Offline recovery", function() shell.run("/recovery.lua") end },
    { "View runtime log", function() shell.run("edit", "/cookieos-data/runtime.log") end },
    { "Exit", function() end },
}

while true do
    term.clear()
    term.setCursorPos(1, 1)
    print("CookieSecurity Applications")
    for index, choice in ipairs(choices) do print(index .. ". " .. choice[1]) end
    write("> ")
    local selected = tonumber(read())
    if choices[selected] then
        choices[selected][2]()
        if selected == #choices then return end
        print("Press any key to return")
        os.pullEvent("key")
    end
end
