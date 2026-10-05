local service = {}

service.manifest = {
    name = "command-terminal", version = "3.4.0", provides = {},
    depends = { "node" },
}

function service.register(context)
    context.supervisor:add("command-terminal", function()
        if not shell or type(shell.run) ~= "function" then error("CraftOS shell API is unavailable") end
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1, 1)
        print("CookieSecurity Command Terminal")
        print("Node: " .. context.config.node .. " | unrestricted local CraftOS access")
        print("Use help for CraftOS commands. Filesystem changes are local and are not sent over the network.")
        shell.run("shell")
        print("Command shell exited. Restarting...")
        sleep(1)
        error("Command shell exited")
    end, { restart = true })
end

return service
