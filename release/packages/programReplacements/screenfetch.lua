local function readTable(path)
    if not fs.exists(path) then return nil end; local handle=fs.open(path,"r");if not handle then return nil end
    local value=textutils.unserialize(handle.readAll());handle.close();return type(value)=="table"and value or nil
end
local config,configError
if fs.exists("/cookieos-node.lua") then
    local chunk,loadError=loadfile("/cookieos-node.lua")
    if not chunk then configError=loadError else
        local ok,value=pcall(chunk)
        if ok and type(value)=="table" then config=value else configError=value end
    end
else configError="/cookieos-node.lua not found" end
local installed=readTable("/cookieos-install/installed.db")or{}
local update=readTable("/cookieos-update/state.db")or{}
term.setTextColor(colors.yellow);print("  COOKIESECURITY");term.setTextColor(colors.white)
print("Version: "..tostring(installed.version or"unknown"));print("Node:    "..tostring(config and config.node or"unconfigured"));print("Mode:    "..tostring(config and config.mode or"unknown"));print("Place:   "..tostring(config and config.location or"unknown"))
if configError then print("Config:  "..tostring(configError)) end
print("Host:    "..tostring(_HOST));print("Uptime:  "..math.floor(os.clock()).."s");print("Storage: "..tostring(fs.getFreeSpace("/")).." bytes free");print("Update:  "..tostring(update.status or"idle"))
local types={};for _,name in ipairs(peripheral.getNames())do local kind=peripheral.getType(name);types[kind]=(types[kind] or 0)+1 end
local summary={};for kind,count in pairs(types)do summary[#summary+1]=kind.."="..count end;table.sort(summary);print("Devices: "..(#summary>0 and table.concat(summary,", ")or"none"))
