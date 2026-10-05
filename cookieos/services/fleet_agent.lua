local service = {}
local Update = require("cookieos.update")

service.manifest = {
    name = "fleet-agent", version = "3.6.0",
    provides = { "fleet.agent.status", "fleet.agent.stage", "fleet.agent.apply", "fleet.agent.rollback" },
    depends = { "node" },
}

local function readState(path)
    if not fs.exists(path) then return {} end
    local handle = fs.open(path, "r"); if not handle then return {} end
    local ok, value = pcall(textutils.unserialize, handle.readAll()); handle.close()
    return ok and type(value) == "table" and value or {}
end

function service.register(context)
    local function authorize(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "updates.manage")
        if not allowed then return nil, reason end
        return true
    end
    local function status()
        local state = readState(context.config.update.statePath)
        return { node = context.config.node, state = state.status or "idle", version = state.version,
            attempts = state.attempts or 0, healthyAt = state.healthyAt }
    end
    context.network:provide("fleet.agent.status", function(payload, packet)
        local allowed, reason = context.authorize(payload, packet, "updates.view")
        if not allowed then return nil, reason end
        return status()
    end)
    context.network:provide("fleet.agent.stage", function(payload, packet)
        local ok, reason = authorize(payload, packet); if not ok then return nil, reason end
        local ref = tostring(payload.ref or "cookieos-v3-rewrite")
        if not ref:match("^[%w%._%/-]+$") or #ref > 100 then return nil, "Invalid release ref" end
        local ran = shell and shell.run and shell.run("/cookieos-update.lua", ref, "/cookieos-node.lua", "--stage-only")
        if not ran then return nil, "Update staging failed" end
        return status()
    end)
    context.network:provide("fleet.agent.apply", function(payload, packet)
        local ok, reason = authorize(payload, packet); if not ok then return nil, reason end
        local applied, err = Update.apply(context.config); if not applied then return nil, err end
        os.queueEvent("cookieos_fleet_reboot")
        return status()
    end)
    context.network:provide("fleet.agent.rollback", function(payload, packet)
        local ok, reason = authorize(payload, packet); if not ok then return nil, reason end
        local rolledBack, err = Update.rollback(context.config); if not rolledBack then return nil, err end
        os.queueEvent("cookieos_fleet_reboot")
        return status()
    end)
    context.supervisor:add("fleet-reboot", function()
        while true do os.pullEvent("cookieos_fleet_reboot"); sleep(1); os.reboot() end
    end)
end

return service
