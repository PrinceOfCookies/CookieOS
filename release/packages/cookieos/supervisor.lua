local Supervisor = {}
Supervisor.__index = Supervisor

function Supervisor.new(log)
    return setmetatable({ log = log, tasks = {} }, Supervisor)
end

function Supervisor:add(name, fn, options)
    assert(type(name) == "string" and type(fn) == "function", "Invalid supervised task")
    table.insert(self.tasks, { name = name, fn = fn, restart = not options or options.restart ~= false })
end

function Supervisor:runner(task)
    return function()
        repeat
            self.log.info("Starting task " .. task.name)
            local ok, err = pcall(task.fn)
            if not ok and tostring(err) == "Terminated" then error(err, 0) end
            if ok then
                self.log.warn("Task exited: " .. task.name)
            else
                self.log.error("Task crashed: " .. task.name .. ": " .. tostring(err))
            end
            if task.restart then sleep(1) end
        until not task.restart
    end
end

function Supervisor:run()
    if #self.tasks == 0 then error("Supervisor has no tasks") end
    local runners = {}
    for _, task in ipairs(self.tasks) do table.insert(runners, self:runner(task)) end
    parallel.waitForAll(table.unpack(runners))
end

return Supervisor
