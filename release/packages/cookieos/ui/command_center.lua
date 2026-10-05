local UI = require("cookieos.ui.monitor")
local center = {}

local tabs = { "Overview", "Map", "Incidents", "People", "Devices", "Alerts", "Tasks", "Policies", "Audit", "Updates", "Sim" }
local function request(context, service, payload)
    local response, err = context.network:request(service, payload)
    if not response then return nil, err end
    if not response.ok then return nil, response.error end
    return response.data
end
local function values(tableValue)
    local result={};for _,value in pairs(tableValue or{})do result[#result+1]=value end;return result
end
local function button(device,x,y,width,label,active)
    device.setCursorPos(x,y);device.setBackgroundColor(active and colors.blue or colors.gray);device.setTextColor(colors.white)
    device.write((" "..label..string.rep(" ",width)):sub(1,width));device.setBackgroundColor(colors.black)
end
local function title(device,text,simulation)
    UI.header(device,(simulation and "[SIMULATION] "or"").."CookieSecurity | "..text,simulation and colors.orange or colors.blue)
end
local function drawTabs(device,active)
    local width=device.getSize();local x=1
    for index,name in ipairs(tabs)do local label=name:sub(1,math.max(3,math.floor(width/#tabs)-1));local w=#label+2;if x+w-1<=width then button(device,x,2,w,label,index==active)end;x=x+w end
end
local function rows(device,start,items,render)
    local _,height=device.getSize();for index,item in ipairs(items or{})do if start+index-1>height then break end;UI.line(device,start+index-1,render(item,index))end
end

function center.run(context, authorize, monitorSide)
    local device,openError=UI.open({side=monitorSide,textScale=0.5});if not device then return nil,openError end
    local side=peripheral.getName and peripheral.getName(device);local active,floor,selected,adding=1,0,nil,false
    local simulation=false
    local function call(service,payload) return request(context,service,authorize(payload or{})) end
    local function render()
        UI.clear(device);local tab=tabs[active];title(device,tab,simulation);drawTabs(device,active)
        if tab=="Overview"then
            local data=call("ops.snapshot")or{nodes={}};UI.line(device,4,"Nodes: "..#(data.nodes or{}).."  Incidents: "..tostring(data.openIncidents or 0).."  Rooms: "..tostring(data.rooms or 0),colors.cyan)
            rows(device,6,data.nodes,function(n)return string.format("%-18s %-7s %3ss %s",n.node,n.mode or"?",n.age or 0,n.location or"")end)
        elseif tab=="Map"then
            local data=call("map.get")or{rooms={}};local alarms=call("alarm.list")or{active={}};local players=call("players.list")or{players={}};local alarmCount=0;for _,alarm in pairs(alarms.active or{})do if alarm.status=="active"then alarmCount=alarmCount+1 end end
            UI.line(device,3,"Floor "..floor.."  [ADD] [DEL] [-] [+]"..(alarmCount>0 and("  ! "..alarmCount.." ALARM")or""),alarmCount>0 and colors.red or colors.yellow)
            for _,room in pairs(data.rooms or{})do if tonumber(room.floor) == floor then
                local x,y=math.max(1,room.x),math.max(4,room.y+3);local width,height=device.getSize()
                if x<=width and y<=height then device.setCursorPos(x,y);device.setBackgroundColor(room.id==selected and colors.orange or room.color or colors.gray);device.setTextColor(colors.white);device.write(UI.trim(room.name or room.id,math.min(room.width or 5,width-x+1)));device.setBackgroundColor(colors.black)end
                if room.world then for _,player in ipairs(players.players or{})do local px,pz=tonumber(player.x),tonumber(player.z);if px and pz and px>=math.min(room.world.x1,room.world.x2)and px<=math.max(room.world.x1,room.world.x2)and pz>=math.min(room.world.z1,room.world.z2)and pz<=math.max(room.world.z1,room.world.z2)then device.setCursorPos(math.min(width,x+math.floor((room.width or 2)/2)),math.min(height,y+1));device.setTextColor(colors.lime);device.write(tostring(player.name or"P"):sub(1,1))end end end
            end end
            if adding then UI.line(device,4,"Touch an empty location for the new room",colors.lime)end
        elseif tab=="Incidents"then local data=call("incident.list")or{incidents={}};rows(device,4,data.incidents,function(v)return string.format("%-10s %-8s %-10s %s",v.id,v.severity,v.status,v.title)end)
        elseif tab=="People"then local data=call("auth.users.list")or{users={}};rows(device,4,data.users,function(v)return string.format("%-16s CL%d %-12s %s",v.name,v.clearance or 0,v.role or"",v.status or"")end)
        elseif tab=="Devices"then local data=call("device.list")or{devices={}};rows(device,4,data.devices,function(v)return string.format("%-18s %-16s %s",v.label,v.type,v.status)end)
        elseif tab=="Alerts"then local alarms=call("alarm.list")or{active={}};local notes=call("notify.history",{limit=10})or{notifications={}};UI.line(device,4,"Active alarms: "..tostring((function()local n=0 for _ in pairs(alarms.active or{})do n=n+1 end return n end)()),colors.red);rows(device,6,notes.notifications,function(v)return string.format("%-9s %s",v.severity,v.message)end)
        elseif tab=="Tasks"then local data=call("task.list")or{tasks={}};rows(device,4,values(data.tasks),function(v)return string.format("%-12s %-9s %-12s %s",v.id,v.status,v.owner or"unassigned",v.title)end)
        elseif tab=="Policies"then local data=call("policy.list")or{policies={}};UI.line(device,3,"Touch a policy row to apply it",colors.yellow);local list=values(data.policies);table.sort(list,function(a,b)return a.id<b.id end);rows(device,4,list,function(v)return(string.format("%-14s %-8s %s",v.id,v.security or"",v.name))end)
        elseif tab=="Audit"then local data=call("audit.query",{limit=30})or{records={}};rows(device,4,data.records,function(v)return string.format("%-5s %-16s %-20s %s",v.id,v.actor,v.action,v.outcome)end)
        elseif tab=="Updates"then local data=call("fleet.status")or{};UI.line(device,4,"Version: "..tostring(data.version));UI.line(device,5,"Plans: "..tostring((function()local n=0 for _ in pairs(data.plans or{})do n=n+1 end return n end)()));rows(device,7,values(data.plans),function(v)return string.format("%-14s %-10s batch %s",v.id,v.status,v.batch)end)
        elseif tab=="Sim"then local data=call("simulation.status")or{active=false,events={}};simulation=data.active==true;UI.line(device,4,data.active and("ACTIVE: "..tostring(data.name))or"Simulation inactive",data.active and colors.orange or colors.lime);UI.line(device,5,"[START] [STOP]  Inject events from terminal commands");rows(device,7,data.events,function(v)return tostring(v.topic)end)
        end
    end
    local function tabAt(x)
        local width=device.getSize();local cursor=1
        for index,name in ipairs(tabs)do local label=name:sub(1,math.max(3,math.floor(width/#tabs)-1));local w=#label+2;if x>=cursor and x<cursor+w then return index end;cursor=cursor+w end
    end
    local timer=os.startTimer(5);render()
    while true do
        local event,a,x,y=os.pullEvent()
        if event=="key"and(a==keys.q or a==keys.backspace)then UI.clear(device);UI.center(device,1,"Command Center closed",colors.lightGray);return true
        elseif event=="timer"and a==timer then timer=os.startTimer(5);render()
        elseif event=="monitor_touch"and(not side or a==side)then
            if y==2 then active=tabAt(x)or active
            elseif tabs[active]=="Map"and y==3 then
                if x>=10 and x<=14 then adding=true elseif x>=16 and x<=20 and selected then call("map.room.remove",{id=selected});selected=nil elseif x>=22 and x<=24 then floor=floor-1 elseif x>=26 and x<=28 then floor=floor+1 end
            elseif tabs[active]=="Map"and y>=4 then
                local data=call("map.get")or{rooms={}};local hit
                for _,room in pairs(data.rooms or{})do if tonumber(room.floor)==floor and y>=room.y+3 and y<room.y+3+(room.height or 1)and x>=room.x and x<room.x+(room.width or 1)then hit=room.id end end
                if hit then selected=hit;adding=false elseif adding then
                    term.setTextColor(colors.yellow);write("Room id: ");local id=read();write("Room name: ");local name=read()
                    call("map.room.set",{id=id,name=name,floor=floor,x=x,y=y-3,width=math.max(5,#name),height=2});adding=false;selected=id
                end
            elseif tabs[active]=="Policies"and y>=4 then local data=call("policy.list")or{policies={}};local list=values(data.policies);table.sort(list,function(l,r)return l.id<r.id end);local policy=list[y-3];if policy then call("policy.apply",{id=policy.id})end
            elseif tabs[active]=="Sim"and y==5 then if x<=9 then call("simulation.start",{name="Command Center exercise"})else call("simulation.stop",{outcome="operator ended"})end end
            render()
        end
    end
end

return center
