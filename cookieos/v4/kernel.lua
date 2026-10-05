local kernel = {}

local function orderServices(services)
    local result, done = {}, {}
    while #result < #services do
        local selected
        for _, service in ipairs(services) do
            if not done[service.name] then
                local ready = true
                for _, dependency in ipairs(service.depends or {}) do if not done[dependency] then ready = false end end
                if ready then selected = service; break end
            end
        end
        if not selected then error("CookieOS v4 service dependency cycle", 2) end
        done[selected.name] = true
        result[#result + 1] = selected
    end
    return result
end

function kernel.new(config, log)
    return { config = config, log = log, services = {}, running = false }
end

function kernel.start(instance, definitions)
    for _, definition in ipairs(orderServices(definitions)) do
        if type(definition.start) ~= "function" then error("Service has no start function: " .. tostring(definition.name), 2) end
        local ok, service = pcall(definition.start, instance)
        if not ok then error("Service failed to start: " .. tostring(definition.name) .. ": " .. tostring(service), 2) end
        instance.services[definition.name] = service or true
    end
    instance.running = true
    return instance
end

function kernel.stop(instance)
    for _, service in pairs(instance.services) do if type(service) == "table" and type(service.stop) == "function" then pcall(service.stop) end end
    instance.running = false
end

return kernel
