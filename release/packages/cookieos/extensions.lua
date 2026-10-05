local extensions = {}

function extensions.load(context, configured)
    local loaded = {}
    local api = {}

    function api.register(definition)
        if type(definition) ~= "table" or type(definition.name) ~= "string" or definition.name == "" then error("Extension requires a name") end
        if loaded[definition.name] then error("Duplicate extension: " .. definition.name) end
        loaded[definition.name] = {
            name = definition.name, version = tostring(definition.version or "0.0.0"),
            description = tostring(definition.description or ""), actions = definition.actions or {},
            health = definition.health,
        }
    end
    function api.emit(topic, payload) return context.publish("extension." .. topic, payload) end
    function api.request(service, payload, timeout) return context.network:request(service, payload, timeout) end
    function api.audit(action, details) if context.audit then return context.audit.write("extension." .. action, { details = details }) end end
    function api.config() return context.config end

    for _, moduleName in ipairs(configured or {}) do
        local ok, module = pcall(require, moduleName)
        if not ok then context.log.error("Extension load failed " .. tostring(moduleName) .. ": " .. tostring(module))
        elseif type(module) ~= "table" or type(module.register) ~= "function" then context.log.error("Invalid extension module " .. tostring(moduleName))
        else
            local registered, err = pcall(module.register, api)
            if not registered then context.log.error("Extension registration failed " .. tostring(moduleName) .. ": " .. tostring(err)) end
        end
    end

    return {
        list = function()
            local result = {}
            for _, extension in pairs(loaded) do
                local healthy, detail = true, "loaded"
                if extension.health then local ok, value, message = pcall(extension.health); healthy, detail = ok and value ~= false, ok and (message or "healthy") or tostring(value) end
                result[#result + 1] = { name=extension.name,version=extension.version,description=extension.description,healthy=healthy,detail=detail }
            end
            table.sort(result,function(a,b)return a.name<b.name end);return result
        end,
        call = function(name, action, data, caller)
            local extension = loaded[tostring(name or "")]; if not extension then return nil, "Extension not found" end
            local handler = extension.actions[tostring(action or "")]; if type(handler) ~= "function" then return nil, "Extension action not found" end
            local ok, result, err = pcall(handler, data, caller, api)
            if not ok then return nil, tostring(result) end
            if result == nil and err then return nil, err end
            return result
        end,
    }
end

return extensions
