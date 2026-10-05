local choices = {
    { "CraftOS shell", function() shell.run("shell") end },
    { "Node information", function() shell.run("/programReplacements/screenfetch.lua") end },
    { "Stage CookieSecurity update", function() shell.run("/cookieos-update.lua", "cookieos-v3-rewrite") end },
    { "Edit node configuration", function() shell.run("edit", "/cookieos-node.lua") end },
    { "Pair this node", function() shell.run("/pair-node.lua") end },
    { "Enroll a node (Command only)", function() shell.run("/command-enroll.lua") end },
    { "Revoke a node (Command only)", function() shell.run("/command-revoke.lua") end },
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
