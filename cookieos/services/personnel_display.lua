local service = {}
local Ui = require("cookieos.ui.monitor")

service.manifest = {
    name = "personnel-display", version = "3.3.0", provides = {},
    depends = { "personnel" }, peripherals = { "monitor" },
}

function service.register(context)
    local options = context.config.personnelDisplay or {}
    local monitor, err = Ui.open(options)
    if not monitor then error(err) end

    local function draw()
        local users = context.personnel.list(options.filter or "all")
        local width, height = monitor.getSize()
        Ui.clear(monitor)
        Ui.header(monitor, "SUBTERRA PERSONNEL", colors.red)
        Ui.center(monitor, 3, tostring(#users) .. " registered users", colors.lime)
        local y = 5
        for _, user in ipairs(users) do
            if y > height then break end
            local line
            if width >= 38 then
                line = string.format("%-4s %-14s %-12s %s", user.clearanceLabel, Ui.trim(user.name, 14), Ui.trim(user.role, 12), user.status)
            else
                line = string.format("%-4s %-12s %s", user.clearanceLabel, Ui.trim(user.name, 12), user.status)
            end
            Ui.line(monitor, y, line, Ui.statusColor(user.status))
            y = y + 1
        end
    end

    context.supervisor:add("personnel-display.draw", function()
        while true do draw(); sleep(options.refreshSeconds or 5) end
    end)
end

return service
