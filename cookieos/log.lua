local log = {}
local path = "/cookieos-data/runtime.log"
local node = "unknown"

local function ensureDirectory()
    local directory = fs.getDir(path)
    if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
end

function log.configure(options)
    options = options or {}
    path = options.path or path
    node = options.node or node
    ensureDirectory()
end

function log.write(level, message)
    ensureDirectory()
    local line = string.format("[%d] [%s] [%s] %s", os.epoch("utc"), level, node, tostring(message))
    local handle = fs.open(path, "a")
    if handle then handle.writeLine(line); handle.close() end
    if level == "ERROR" then printError(line) else print(line) end
end

function log.info(message) log.write("INFO", message) end
function log.warn(message) log.write("WARN", message) end
function log.error(message) log.write("ERROR", message) end

return log
