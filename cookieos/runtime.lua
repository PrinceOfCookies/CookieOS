local Config = require("cookieos.config")
local Log = require("cookieos.log")
local Network = require("cookieos.net.network")
local Supervisor = require("cookieos.supervisor")
local Update = require("cookieos.update")

local runtime = {}

local builtins = {
    node = "cookieos.services.node",
    security = "cookieos.services.security",
    terminal = "cookieos.services.terminal",
    auth = "cookieos.services.auth",
    audit = "cookieos.services.audit",
    ["player-tracker"] = "cookieos.services.player_tracker",
    maintenance = "cookieos.services.maintenance",
    events = "cookieos.services.events",
    personnel = "cookieos.services.personnel",
    ["personnel-display"] = "cookieos.services.personnel_display",
    pairing = "cookieos.services.pairing",
}

local function resolveService(name)
    local moduleName = builtins[name] or name
    local module = require(moduleName)
    if type(module) ~= "table" or type(module.register) ~= "function" then
        error("Service module must export register(context): " .. moduleName)
    end
    module.manifest = module.manifest or { name = name, version = "0.0.0", provides = {} }
    return { configuredName = name, moduleName = moduleName, module = module, manifest = module.manifest }
end

local function validateServices(resolved)
    local available = {}
    for _, entry in ipairs(resolved) do
        local manifest = entry.manifest
        if type(manifest.name) ~= "string" or manifest.name == "" then error("Service manifest requires a name: " .. entry.moduleName) end
        if available[manifest.name] then error("Duplicate service manifest: " .. manifest.name) end
        available[manifest.name] = true
    end
    for _, entry in ipairs(resolved) do
        for _, dependency in ipairs(entry.manifest.depends or {}) do
            if not available[dependency] then error(entry.manifest.name .. " requires missing service " .. dependency) end
        end
        for _, requirement in ipairs(entry.manifest.peripherals or {}) do
            local peripheralType = type(requirement) == "table" and requirement.type or requirement
            local optional = type(requirement) == "table" and requirement.optional
            if not optional and not peripheral.find(peripheralType) then
                error(entry.manifest.name .. " requires peripheral " .. tostring(peripheralType))
            end
        end
    end
end

local function orderServices(resolved)
    local ordered, completed, added = {}, {}, {}
    local authPending = false
    for _, entry in ipairs(resolved) do
        if entry.manifest.name == "auth" then authPending = true end
    end
    while #ordered < #resolved do
        local selected
        for _, entry in ipairs(resolved) do
            if not added[entry] then
                local ready = true
                for _, dependency in ipairs(entry.manifest.depends or {}) do
                    if not completed[dependency] then ready = false; break end
                end
                if ready and (not authPending or entry.manifest.name == "auth") then
                    selected = entry
                    break
                end
            end
        end
        if not selected then error("Circular service dependency detected") end
        table.insert(ordered, selected)
        added[selected] = true
        completed[selected.manifest.name] = true
        if selected.manifest.name == "auth" then authPending = false end
    end
    return ordered
end

function runtime.start(configPath)
    local nodeConfig = Config.load(configPath)
    Log.configure({ node = nodeConfig.node })

    local supervisor = Supervisor.new(Log)
    local network = Network.new(nodeConfig, Log)
    local context = { config = nodeConfig, log = Log, network = network, supervisor = supervisor, registry = {} }
    context.authorize = function(payload, packet, permission)
        if context.auth then return context.auth.authorizeRequest(payload, packet, permission) end
        local response, requestError = network:request("auth.authorize", {
            session = payload and payload.session,
            origin = packet and packet.source,
            permission = permission,
        })
        if not response then return false, requestError end
        if not response.ok then return false, response.error end
        return response.data.allowed, response.data.reason, response.data
    end
    context.publish = function(topic, payload, retain)
        if context.events then return context.events.publish(topic, payload, { retain = retain }) end
        if not network:resolve("events.publish") then return nil, "Event broker unavailable" end
        local response, err = network:request("events.publish", {
            topic = topic, payload = payload, retain = retain,
        })
        if not response then return nil, err end
        if not response.ok then return nil, response.error end
        return response.data
    end

    -- Auth establishes the authorization boundary used by other services, so it
    -- must register before them regardless of configuration order.
    local resolved = {}
    for _, name in ipairs(nodeConfig.services) do
        table.insert(resolved, resolveService(name))
    end
    validateServices(resolved)
    for _, entry in ipairs(orderServices(resolved)) do
        entry.module.register(context)
        for _, provided in ipairs(entry.manifest.provides or {}) do
            if not network.services[provided] then error(entry.manifest.name .. " did not register declared endpoint " .. provided) end
        end
        context.registry[entry.manifest.name] = {
            name = entry.manifest.name,
            version = entry.manifest.version,
            provides = entry.manifest.provides or {},
            depends = entry.manifest.depends or {},
            health = entry.module.health,
        }
    end
    require("cookieos.legacy.subterra").register(context)

    supervisor:add("network", function()
        local ok, err = pcall(function() network:run() end)
        network.running = false
        if not ok then error(err, 0) end
    end)
    supervisor:add("boot-health", function()
        while not network.running or #network.transports == 0 do sleep(1) end
        sleep(10)
        if network.running and network.lastActivity and os.clock() - network.lastActivity < 6 then
            Update.markHealthy(nodeConfig)
        else
            error("Network did not reach healthy state")
        end
    end, { restart = false })
    Log.info("CookieOS v3 node booting in " .. nodeConfig.mode .. " mode")
    supervisor:run()
end

return runtime
