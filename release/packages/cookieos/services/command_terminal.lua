local service = {}

service.manifest = {
    name = "command-terminal", version = "3.4.0", provides = {},
    depends = { "node", "command-authority" },
}

function service.register(context)
    context.supervisor:add("command-terminal", function()
        if not shell or type(shell.run) ~= "function" then error("CraftOS shell API is unavailable") end
        local path = shell.path()
        if not path:find("/programReplacements", 1, true) then shell.setPath("/programReplacements:" .. path) end
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1, 1)
        print("CookieSecurity Command Authority")
        print("Node: " .. context.config.node .. " | unrestricted local CraftOS access")
        local authenticated, authError
        while not authenticated do
            local status = context.commandAuthority.status()
            if status.locked then
                printError("GLOBAL LOCKDOWN: " .. tostring(status.reason or "authentication failure"))
                authenticated, authError = context.commandAuthority.override()
            else authenticated, authError = context.commandAuthority.authenticate() end
            if not authenticated then
                printError(authError or "Command access denied")
                print("The lockdown remains active. Check the diagnostics above, correct the detector/GPS issue, and retry.")
                print("Press any key to retry, or Ctrl+T to terminate the terminal task.")
                os.pullEvent("key")
            end
        end
        print("CL6 physical authentication accepted. Local unrestricted shell opened.")
        print("Use normal CraftOS help for shell commands. Run 'cs' for CookieSecurity tools.")
        print("CookieSecurity tools: cs, nodeinfo, logs, update, recover, enroll, revoke")
        shell.run("shell")
        print("Command shell exited. Restarting...")
        sleep(1)
        error("Command shell exited")
    end, { restart = true })
end

return service
