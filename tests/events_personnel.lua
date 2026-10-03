package.path = package.path .. ";/?.lua;/?/init.lua"

local handlers, sent = {}, {}
local context = {
    config = {
        node = "core", mode = "server",
        events = { maxTopics = 8, retainedPerTopic = 2, subscriptionSeconds = 60 },
    },
    log = { error = function(message) error(message) end },
    authorize = function() return true end,
    network = {
        provide = function(_, name, handler) handlers[name] = handler end,
        send = function(_, kind, fields) table.insert(sent, { kind = kind, fields = fields }) end,
    },
}

require("cookieos.services.events").register(context)
local subscription = handlers["events.subscribe"]({ topic = "security.changed" }, { source = "display" })
assert(subscription.topic == "security.changed")
local published = handlers["events.publish"]({
    topic = "security.changed", payload = { level = "RED" },
}, { source = "core", localRequest = true })
assert(published.payload.level == "RED")
assert(#sent == 1 and sent[1].fields.destination == "display")
local recent = handlers["events.recent"]({ topic = "security.changed" }, { source = "terminal" })
assert(#recent.events == 1)

local personnelHandlers = {}
local personnelContext = {
    auth = { listUsers = function()
        return {
            { name = "Alice", clearance = 2, clearanceLabel = "CL2", role = "Engineer", status = "Active" },
            { name = "Visitor", clearance = 0, clearanceLabel = "CL0", role = "Visitor", status = "Active" },
            { name = "Former", clearance = 4, clearanceLabel = "CL4", role = "Security", status = "FIRED" },
        }
    end },
    authorize = function() return true end,
    network = { provide = function(_, name, handler) personnelHandlers[name] = handler end },
    publish = function() end,
}
require("cookieos.services.personnel").register(personnelContext)
assert(personnelHandlers["personnel.list"]({ filter = "visitors" }, {}).total == 1)
assert(personnelHandlers["personnel.list"]({ filter = "fired" }, {}).total == 1)
assert(personnelHandlers["personnel.search"]({ query = "engine" }, {}).users[1].name == "Alice")

print("All 6 event and personnel tests passed")
