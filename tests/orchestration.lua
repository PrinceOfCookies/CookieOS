package.path="./?.lua;./?/init.lua;"..package.path
local files={}
fs={exists=function(p)return files[p]~=nil end,getDir=function(p)return p:match("^(.*)/[^/]+$")or""end,makeDir=function()end,delete=function(p)files[p]=nil end,move=function(a,b)files[b],files[a]=files[a],nil end,getFreeSpace=function()return 100000 end,
open=function(path,mode)local buffer=mode=="a"and(files[path]or"")or"";if mode=="r"then if not files[path]then return nil end;return{readAll=function()return files[path]end,close=function()end}end;return{write=function(v)buffer=buffer..v end,writeLine=function(v)buffer=buffer..v.."\n"end,close=function()files[path]=buffer end}end}
textutils={serialize=function(v)local function e(x)if type(x)=="table"then local o={"{"};for k,c in pairs(x)do o[#o+1]="["..e(k).."]="..e(c)..","end;o[#o+1]="}";return table.concat(o)end;return type(x)=="string"and string.format("%q",x)or tostring(x)end;return e(v)end,unserialize=function(v)return assert(load("return "..v))()end}
peripheral={getNames=function()return{"left","top"}end,getType=function(n)return n=="left"and"monitor"or"speaker"end,isPresent=function()return true end}
local handlers,published={},{}
local context={config={node="core",mode="server",location="HQ",orchestration={}},network={routes={},provide=function(_,n,h)handlers[n]=h end,request=function(_,name,payload)return{ok=true,data={service=name,payload=payload}}end},
authorize=function()return true,"Allowed",{user="admin",clearance=5,zones={"*"}}end,publish=function(topic,payload)published[#published+1]={topic=topic,payload=payload};return true end,audit={write=function()end},log={error=function()end},supervisor={add=function()end},
security={setInternal=function(level)return{level=level}end},auth={consumeApproval=function(id,action)if id=="approved"and action=="policy:lockdown"then return true end;return nil,"approval required"end},extensions={list=function()return{{name="test"}}end,call=function()return{ok=true}end}}
require("cookieos.services.orchestration").register(context)
local packet={source="terminal"};local function call(name,p)local result,err=handlers[name](p or{},packet);assert(result,err);return result end
assert(call("policy.list").policies.normal)
local denied,reason=handlers["policy.apply"]({id="lockdown"},packet);assert(not denied and reason=="approval required")
assert(call("policy.apply",{id="lockdown",approval="approved"}).policy.id=="lockdown")
local drill=call("alarm.drill",{pattern="fire",message="Test"});assert(drill.drill==true)
assert(call("device.list").total==2)
local run=call("workflow.start",{id="fire"});assert(run.status=="active")
local task=call("task.set",{title="Inspect door",owner="guard"});assert(task.status=="open")
assert(call("simulation.start",{name="Exercise"}).active)
local simulated=call("policy.apply",{id="normal"});assert(simulated.simulated==true)
assert(call("simulation.inject",{topic="node.offline",payload={node="relay"}}).topic=="node.offline")
assert(call("simulation.stop",{outcome="passed"}).active==false)
assert(#call("extension.list").extensions==1)
print("Orchestration policy, alarm, workflow, task, simulation, device, and extension tests passed.")
