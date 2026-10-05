local service = {}

service.manifest = {
    name = "command-terminal", version = "3.4.0", provides = {},
    depends = { "node", "command-authority" },
}

function service.register(context)
    context.supervisor:add("command-terminal", function()
        if not shell or type(shell.run) ~= "function" then error("CraftOS shell API is unavailable") end
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1, 1)
        print("CookieSecurity Command Authority")
        print("Node: " .. context.config.node .. " | unrestricted local CraftOS access")
        local status = context.commandAuthority.status()
        local authenticated, authError
        if status.locked then
            printError("GLOBAL LOCKDOWN: " .. tostring(status.reason or "authentication failure"))
            authenticated, authError = context.commandAuthority.override()
        else authenticated, authError = context.commandAuthority.authenticate() end
        if not authenticated then error(authError or "Command access denied") end
        print("CL6 physical authentication accepted. Local unrestricted shell opened.")
        print("Use help for CraftOS commands. Filesystem changes are local and are not sent over the network.")
        shell.run("shell")
        print("Command shell exited. Restarting...")
        sleep(1)
        error("Command shell exited")
    end, { restart = true })
end

return service
