local service = {}

service.manifest = {
    name = "orchestration", version = "3.7.0",
    provides = {
        "policy.list", "policy.set", "policy.apply", "policy.active",
        "alarm.list", "alarm.pattern.set", "alarm.trigger", "alarm.ack", "alarm.silence", "alarm.drill",
        "device.list", "device.rename", "device.check", "device.template.set", "device.template.apply",
        "workflow.list", "workflow.set", "workflow.start", "workflow.advance",
        "notify.send", "notify.subscribe", "notify.history",
        "task.list", "task.set", "task.update", "patrol.route.set", "patrol.checkpoint", "handover.add", "handover.list",
        "simulation.status", "simulation.start", "simulation.inject", "simulation.stop",
        "extension.list", "extension.call",
    },
    depends = { "node" },
}

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = clone(child) end; return result
end

local function cleanId(value)
    value = tostring(value or "")
    return #value > 0 and #value <= 48 and value:match("^[%w_%-]+$") and value or nil
end

local function load(path)
    if not fs.exists(path) then return {} end
    local handle = fs.open(path, "r"); if not handle then return {} end
    local ok, value = pcall(textutils.unserialize, handle.readAll()); handle.close()
    return ok and type(value) == "table" and value or {}
end

local function save(path, value)
    local directory = fs.getDir(path); if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
    local temporary = path .. ".new"; local handle = fs.open(temporary, "w")
    if not handle then return nil, "Cannot write orchestration state" end
    handle.write(textutils.serialize(value)); handle.close()
    if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
    if fs.exists(path) then fs.move(path, path .. ".bak") end
    fs.move(temporary, path); return true
end

local function count(values) local n=0 for _ in pairs(values or {}) do n=n+1 end return n end

function service.register(context)
    local options = context.config.orchestration or {}
    local path = options.dataPath or "/cookieos-data/orchestration.db"
    local state = load(path)
    state.policies = state.policies or {
        normal = { id="normal", name="Normal operations", security="GREEN", actions={} },
        night = { id="night", name="Night mode", security="YELLOW", actions={{type="lock-zone",zone="restricted"}} },
        restricted = { id="restricted", name="Restricted access", security="RED", actions={{type="lock-zone",zone="all"}} },
        evacuation = { id="evacuation", name="Evacuation", security="RED", actions={{type="unlock-zone",zone="egress"},{type="alarm",pattern="evacuation"}} },
        lockdown = { id="lockdown", name="Facility lockdown", security="BLACK", actions={{type="lock-zone",zone="all"},{type="alarm",pattern="lockdown"}} },
    }
    state.alarms = state.alarms or {}
    state.alarmPatterns = state.alarmPatterns or {
        intrusion={sound="minecraft:block.bell.use",count=5,priority="emergency"},
        fire={sound="minecraft:block.note_block.bell",count=8,priority="emergency"},
        evacuation={sound="minecraft:block.note_block.bell",count=6,priority="urgent"},
        lockdown={sound="minecraft:entity.wither.spawn",count=3,priority="emergency"},
        medical={sound="minecraft:block.note_block.chime",count=4,priority="urgent"},
    }
    state.workflows = state.workflows or {
        fire={id="fire",name="Fire",steps={"Open an incident","Sound fire alarm","Unlock egress routes","Account for personnel","Issue all-clear"}},
        intrusion={id="intrusion",name="Intrusion",steps={"Open an incident","Apply restricted policy","Locate personnel","Assign response","Resolve or escalate"}},
        missing={id="missing",name="Missing person",steps={"Open an incident","Search personnel cache","Assign search zones","Record contact","Close incident"}},
        medical={id="medical",name="Medical emergency",steps={"Open an incident","Send medical alert","Unlock response route","Assign responder","Record resolution"}},
        evacuation={id="evacuation",name="Evacuation",steps={"Apply evacuation policy","Broadcast instructions","Unlock egress routes","Account for personnel","Issue all-clear"}},
        shelter={id="shelter",name="Shelter in place",steps={"Apply lockdown policy","Broadcast shelter instructions","Lock external doors","Account for personnel","Issue all-clear"}},
        communications={id="communications",name="Communications failure",steps={"Open incident","Check node health","Activate backup authority","Assign runners","Restore and verify"}},
    }
    state.runs, state.notifications, state.subscriptions = state.runs or {}, state.notifications or {}, state.subscriptions or {}
    state.tasks, state.patrols, state.deviceNames = state.tasks or {}, state.patrols or {}, state.deviceNames or {}
    state.deviceTemplates, state.handovers = state.deviceTemplates or {}, state.handovers or {}
    state.deviceSeen = state.deviceSeen or {}
    state.simulation = state.simulation or { active=false, events={} }
    state.sequence = state.sequence or 0

    local function persist() return save(path, state) end
    local function authorize(payload, packet, permission)
        local allowed, reason, identity = context.authorize(payload, packet, permission)
        if not allowed then return nil, reason end
        return identity or true
    end
    local function record(action, payload, packet, details)
        if context.audit then context.audit.write(action, { actor=payload and payload.actor or "session", node=packet and packet.source, details=details }) end
    end
    local function publish(topic, payload)
        if state.simulation.active then
            state.simulation.events[#state.simulation.events+1] = { at=os.epoch("utc"), topic=topic, payload=clone(payload) }
            while #state.simulation.events > 200 do table.remove(state.simulation.events,1) end
            persist(); return { simulated=true }
        end
        return context.publish(topic,payload)
    end
    local function notification(message, severity, channels, source)
        state.sequence=state.sequence+1
        local item={id="NOT-"..state.sequence,at=os.epoch("utc"),message=tostring(message),severity=severity or "info",channels=clone(channels or {"monitor"}),source=source}
        state.notifications[#state.notifications+1]=item; while #state.notifications>200 do table.remove(state.notifications,1) end
        if not state.simulation.active then for _,channel in ipairs(item.channels)do
            if channel=="chat"and context.chat then context.chat.send("["..item.severity.."] "..item.message)
            elseif channel=="speaker"and context.audio then context.audio.announce(item.message,item.severity=="emergency"and"emergency"or"urgent")end
        end end
        publish("notification",item); persist(); return item
    end
    local function execute(actions, source)
        local result={}
        for _,action in ipairs(actions or{}) do
            local kind=tostring(action.type or"")
            if state.simulation.active then
                result[#result+1]={type=kind,simulated=true}; publish("simulation.action",{source=source,action=action})
            elseif kind=="security" and context.security then
                local value,err=context.security.setInternal(action.level,"policy:"..source);result[#result+1]={type=kind,ok=value~=nil,error=err}
            elseif kind=="lock-zone" or kind=="unlock-zone" then
                local response=context.network:request("access.set",{zone=action.zone or"all",locked=kind=="lock-zone",actor="policy:"..source})
                result[#result+1]={type=kind,ok=response and response.ok==true}
            elseif kind=="alarm" then
                local pattern=state.alarmPatterns[action.pattern or"intrusion"] or state.alarmPatterns.intrusion
                context.network:request("audio.alarm",{count=pattern.count,actor="policy:"..source});result[#result+1]={type=kind,ok=true}
            elseif kind=="announce" then
                context.network:request("audio.announce",{message=action.message,priority=action.priority,actor="policy:"..source});result[#result+1]={type=kind,ok=true}
            end
        end
        return result
    end

    context.network:provide("policy.list",function(payload,packet)local ok,e=authorize(payload,packet,"policy.view");if not ok then return nil,e end return{policies=clone(state.policies),active=state.activePolicy}end)
    context.network:provide("policy.set",function(payload,packet)
        local ok,e=authorize(payload,packet,"policy.manage");if not ok then return nil,e end local id=cleanId(payload.id);if not id then return nil,"Invalid policy id"end
        if type(payload.actions)~="table"then return nil,"Policy actions are required"end
        state.policies[id]={id=id,name=tostring(payload.name or id),security=payload.security,actions=clone(payload.actions),schedule=clone(payload.schedule)};persist();record("policy.set",payload,packet,{id=id});return clone(state.policies[id])
    end)
    context.network:provide("policy.apply",function(payload,packet)
        local ok,e=authorize(payload,packet,"policy.apply");if not ok then return nil,e end local policy=state.policies[tostring(payload.id or"")];if not policy then return nil,"Policy not found"end
        if (policy.id=="lockdown"or policy.id=="restricted")and context.auth then local approved,approvalError=context.auth.consumeApproval(payload.approval,"policy:"..policy.id);if not approved then return nil,approvalError end end
        local actions=clone(policy.actions);if policy.security then table.insert(actions,1,{type="security",level=policy.security})end
        local results=execute(actions,policy.id);state.activePolicy=policy.id;state.policyChangedAt=os.epoch("utc");persist();record("policy.apply",payload,packet,{id=policy.id,simulation=state.simulation.active});notification("Policy applied: "..policy.name,"warning",{"monitor","chat"},packet.source);return{policy=clone(policy),results=results,simulated=state.simulation.active}
    end)
    context.network:provide("policy.active",function(payload,packet)local ok,e=authorize(payload,packet,"policy.view");if not ok then return nil,e end return{id=state.activePolicy,changedAt=state.policyChangedAt,simulation=state.simulation.active}end)

    context.network:provide("alarm.list",function(payload,packet)local ok,e=authorize(payload,packet,"alarms.view");if not ok then return nil,e end return{active=clone(state.alarms),patterns=clone(state.alarmPatterns)}end)
    context.network:provide("alarm.pattern.set",function(payload,packet)local ok,e=authorize(payload,packet,"alarms.manage");if not ok then return nil,e end local id=cleanId(payload.id);if not id then return nil,"Invalid alarm pattern id"end state.alarmPatterns[id]={sound=tostring(payload.sound or"minecraft:block.bell.use"),count=math.max(1,math.min(20,tonumber(payload.count)or 3)),priority=tostring(payload.priority or"urgent"),escalationSeconds=math.max(10,tonumber(payload.escalationSeconds)or 60)};persist();return clone(state.alarmPatterns[id])end)
    local function triggerAlarm(payload,packet,drill)
        local ok,e=authorize(payload,packet,"alarms.manage");if not ok then return nil,e end local patternId=cleanId(payload.pattern)or"intrusion";local pattern=state.alarmPatterns[patternId];if not pattern then return nil,"Alarm pattern not found"end
        state.sequence=state.sequence+1;local id="ALM-"..state.sequence;local alarm={id=id,pattern=patternId,zone=payload.zone or"all",message=payload.message,status="active",drill=drill==true,startedAt=os.epoch("utc"),acknowledgements={}}
        state.alarms[id]=alarm;if drill or state.simulation.active then publish("alarm.drill",clone(alarm))else context.network:request("audio.alarm",{count=pattern.count,actor="alarm:"..id});publish("alarm.started",clone(alarm))end
        notification((drill and"DRILL: "or"")..(payload.message or("Alarm "..patternId)),pattern.priority,{"monitor","chat","speaker"},packet.source);persist();record("alarm.trigger",payload,packet,{id=id,drill=drill});return clone(alarm)
    end
    context.network:provide("alarm.trigger",function(payload,packet)return triggerAlarm(payload,packet,false)end)
    context.network:provide("alarm.drill",function(payload,packet)return triggerAlarm(payload,packet,true)end)
    context.network:provide("alarm.ack",function(payload,packet)local identity,e=authorize(payload,packet,"alarms.ack");if not identity then return nil,e end local alarm=state.alarms[tostring(payload.id or"")];if not alarm then return nil,"Alarm not found"end alarm.acknowledgements[#alarm.acknowledgements+1]={at=os.epoch("utc"),source=packet.source};persist();return clone(alarm)end)
    context.network:provide("alarm.silence",function(payload,packet)local ok,e=authorize(payload,packet,"alarms.manage");if not ok then return nil,e end local alarm=state.alarms[tostring(payload.id or"")];if not alarm then return nil,"Alarm not found"end alarm.status="silenced";alarm.silencedAt=os.epoch("utc");context.network:request("audio.stop",{actor="alarm:"..alarm.id});persist();record("alarm.silence",payload,packet,{id=alarm.id});return clone(alarm)end)

    local function devices()
        local result,online={},{ };for _,name in ipairs(peripheral.getNames())do local kind=peripheral.getType(name);online[name]=true;result[#result+1]={name=name,label=state.deviceNames[name]or name,type=kind,status="online",node=context.config.node,reason="Peripheral is attached and responding"}end
        for name,seen in pairs(state.deviceSeen)do if not online[name]then result[#result+1]={name=name,label=state.deviceNames[name]or name,type=seen.type,status="offline",node=context.config.node,lastSeen=seen.lastSeen,reason="Peripheral disappeared from the local peripheral bus; check cable, chunk loading, and replacement type"}end end
        table.sort(result,function(a,b)return a.label<b.label end);return result
    end
    context.network:provide("device.list",function(payload,packet)local ok,e=authorize(payload,packet,"devices.view");if not ok then return nil,e end return{devices=devices(),total=#devices()}end)
    context.network:provide("device.rename",function(payload,packet)local ok,e=authorize(payload,packet,"devices.manage");if not ok then return nil,e end if not peripheral.isPresent(payload.name)then return nil,"Peripheral not found"end state.deviceNames[payload.name]=tostring(payload.label or payload.name):sub(1,40);persist();return{name=payload.name,label=state.deviceNames[payload.name]}end)
    context.network:provide("device.check",function(payload,packet)local ok,e=authorize(payload,packet,"devices.view");if not ok then return nil,e end local list=devices();return{devices=list,online=#list,checkedAt=os.epoch("utc"),freeSpace=fs.getFreeSpace and fs.getFreeSpace("/")or nil,fuel=turtle and turtle.getFuelLevel and turtle.getFuelLevel()or nil}end)
    context.network:provide("device.template.set",function(payload,packet)local ok,e=authorize(payload,packet,"devices.manage");if not ok then return nil,e end local id=cleanId(payload.id);if not id then return nil,"Invalid template id"end state.deviceTemplates[id]={id=id,type=payload.type,label=payload.label,settings=clone(payload.settings or{})};persist();return clone(state.deviceTemplates[id])end)
    context.network:provide("device.template.apply",function(payload,packet)local ok,e=authorize(payload,packet,"devices.manage");if not ok then return nil,e end local template=state.deviceTemplates[tostring(payload.id or"")];if not template then return nil,"Template not found"end;if not peripheral.isPresent(payload.name)then return nil,"Peripheral not found"end;if template.type and peripheral.getType(payload.name)~=template.type then return nil,"Peripheral type does not match template"end;if template.label then state.deviceNames[payload.name]=template.label end;persist();return{name=payload.name,template=template.id,label=state.deviceNames[payload.name],settings=clone(template.settings)}end)

    context.network:provide("workflow.list",function(payload,packet)local ok,e=authorize(payload,packet,"workflows.view");if not ok then return nil,e end return{workflows=clone(state.workflows),runs=clone(state.runs)}end)
    context.network:provide("workflow.set",function(payload,packet)local ok,e=authorize(payload,packet,"workflows.manage");if not ok then return nil,e end local id=cleanId(payload.id);if not id or type(payload.steps)~="table"then return nil,"Workflow requires id and steps"end state.workflows[id]={id=id,name=tostring(payload.name or id),steps=clone(payload.steps),policy=payload.policy};persist();return clone(state.workflows[id])end)
    context.network:provide("workflow.start",function(payload,packet)local ok,e=authorize(payload,packet,"workflows.manage");if not ok then return nil,e end local workflow=state.workflows[tostring(payload.id or"")];if not workflow then return nil,"Workflow not found"end state.sequence=state.sequence+1;local id="RUN-"..state.sequence;state.runs[id]={id=id,workflow=workflow.id,status="active",step=1,startedAt=os.epoch("utc"),owner=payload.owner};persist();publish("workflow.started",clone(state.runs[id]));return clone(state.runs[id])end)
    context.network:provide("workflow.advance",function(payload,packet)local ok,e=authorize(payload,packet,"workflows.manage");if not ok then return nil,e end local run=state.runs[tostring(payload.id or"")];if not run then return nil,"Workflow run not found"end local workflow=state.workflows[run.workflow];run.step=math.min(#workflow.steps,(run.step or 1)+1);if payload.complete or run.step>=#workflow.steps then run.status="complete";run.completedAt=os.epoch("utc")end persist();publish("workflow.updated",clone(run));return clone(run)end)

    context.network:provide("notify.send",function(payload,packet)local ok,e=authorize(payload,packet,"notifications.send");if not ok then return nil,e end return notification(payload.message,payload.severity,payload.channels,packet.source)end)
    context.network:provide("notify.subscribe",function(payload,packet)local ok,e=authorize(payload,packet,"notifications.subscribe");if not ok then return nil,e end state.subscriptions[packet.source]={severity=payload.severity or"info",topics=clone(payload.topics or{}),updatedAt=os.epoch("utc")};persist();return clone(state.subscriptions[packet.source])end)
    context.network:provide("notify.history",function(payload,packet)local ok,e=authorize(payload,packet,"notifications.view");if not ok then return nil,e end local result={};local limit=math.max(1,math.min(tonumber(payload.limit)or 50,200));for i=#state.notifications,math.max(1,#state.notifications-limit+1),-1 do result[#result+1]=state.notifications[i]end return{notifications=result,total=#state.notifications}end)

    context.network:provide("task.list",function(payload,packet)local ok,e=authorize(payload,packet,"tasks.view");if not ok then return nil,e end return{tasks=clone(state.tasks),patrols=clone(state.patrols)}end)
    context.network:provide("task.set",function(payload,packet)local ok,e=authorize(payload,packet,"tasks.manage");if not ok then return nil,e end local id=cleanId(payload.id);if not id then state.sequence=state.sequence+1;id="TASK-"..state.sequence end state.tasks[id]={id=id,title=tostring(payload.title or"Untitled task"),owner=payload.owner,zone=payload.zone,dueAt=payload.dueAt,status=payload.status or"open",priority=payload.priority or"normal",updatedAt=os.epoch("utc")};persist();publish("task.changed",clone(state.tasks[id]));return clone(state.tasks[id])end)
    context.network:provide("task.update",function(payload,packet)local ok,e=authorize(payload,packet,"tasks.manage");if not ok then return nil,e end local task=state.tasks[tostring(payload.id or"")];if not task then return nil,"Task not found"end if payload.status then task.status=payload.status end;if payload.owner then task.owner=payload.owner end;task.note=payload.note or task.note;task.updatedAt=os.epoch("utc");persist();return clone(task)end)
    context.network:provide("patrol.route.set",function(payload,packet)local ok,e=authorize(payload,packet,"tasks.manage");if not ok then return nil,e end local id=cleanId(payload.id);if not id or type(payload.checkpoints)~="table"then return nil,"Route id and checkpoints are required"end state.patrols[id]={route=id,checkpoints=clone(payload.checkpoints),intervalSeconds=math.max(30,tonumber(payload.intervalSeconds)or 300),checks={},updatedAt=os.epoch("utc")};persist();return clone(state.patrols[id])end)
    context.network:provide("patrol.checkpoint",function(payload,packet)local ok,e=authorize(payload,packet,"tasks.update");if not ok then return nil,e end local route=cleanId(payload.route);local checkpoint=cleanId(payload.checkpoint);if not route or not checkpoint then return nil,"Route and checkpoint are required"end state.patrols[route]=state.patrols[route]or{route=route,checks={}};state.patrols[route].checks[#state.patrols[route].checks+1]={checkpoint=checkpoint,at=os.epoch("utc"),source=packet.source};persist();publish("patrol.checkpoint",{route=route,checkpoint=checkpoint});return clone(state.patrols[route])end)
    context.network:provide("handover.add",function(payload,packet)local ok,e=authorize(payload,packet,"tasks.update");if not ok then return nil,e end local item={at=os.epoch("utc"),source=packet.source,note=tostring(payload.note or""):sub(1,500)};state.handovers[#state.handovers+1]=item;while#state.handovers>100 do table.remove(state.handovers,1)end;persist();return item end)
    context.network:provide("handover.list",function(payload,packet)local ok,e=authorize(payload,packet,"tasks.view");if not ok then return nil,e end return{notes=clone(state.handovers)}end)

    context.network:provide("simulation.status",function(payload,packet)local ok,e=authorize(payload,packet,"simulation.view");if not ok then return nil,e end return clone(state.simulation)end)
    context.network:provide("simulation.start",function(payload,packet)local ok,e=authorize(payload,packet,"simulation.manage");if not ok then return nil,e end if state.simulation.active then return nil,"Simulation already active"end state.simulation={active=true,name=tostring(payload.name or"Exercise"),startedAt=os.epoch("utc"),events={}};persist();record("simulation.start",payload,packet,{name=state.simulation.name});return clone(state.simulation)end)
    context.network:provide("simulation.inject",function(payload,packet)local ok,e=authorize(payload,packet,"simulation.manage");if not ok then return nil,e end if not state.simulation.active then return nil,"Simulation is not active"end local event={at=os.epoch("utc"),topic=tostring(payload.topic or"simulation.event"),payload=clone(payload.payload or{})};state.simulation.events[#state.simulation.events+1]=event;persist();context.publish("simulation.injected",event);return event end)
    context.network:provide("simulation.stop",function(payload,packet)local ok,e=authorize(payload,packet,"simulation.manage");if not ok then return nil,e end state.simulation.active=false;state.simulation.stoppedAt=os.epoch("utc");state.simulation.outcome=payload.outcome;persist();record("simulation.stop",payload,packet,{outcome=payload.outcome});return clone(state.simulation)end)

    context.network:provide("extension.list",function(payload,packet)local ok,e=authorize(payload,packet,"extensions.view");if not ok then return nil,e end return{extensions=context.extensions and context.extensions.list()or{}}end)
    context.network:provide("extension.call",function(payload,packet)local ok,e=authorize(payload,packet,"extensions.call");if not ok then return nil,e end if not context.extensions then return nil,"Extension host unavailable"end return context.extensions.call(payload.extension,payload.action,payload.data,{source=packet.source})end)

    context.orchestration={state=state,notification=notification,execute=execute}
    context.supervisor:add("device-health",function()while true do
        local current={};for _,name in ipairs(peripheral.getNames())do current[name]=peripheral.getType(name);local previous=state.deviceSeen[name];if not previous then notification("New peripheral detected: "..name.." ("..tostring(current[name])..")","info",{"monitor"},"device-health")elseif previous.offlineAt or previous.type~=current[name]then notification("Peripheral restored or replaced: "..name.." ("..tostring(current[name])..")","info",{"monitor"},"device-health")end;state.deviceSeen[name]={type=current[name],lastSeen=os.epoch("utc")}end
        for name,seen in pairs(state.deviceSeen)do if not current[name]and not seen.offlineAt then seen.offlineAt=os.epoch("utc");notification("Peripheral offline: "..name,"warning",{"monitor","chat"},"device-health")elseif current[name]then seen.offlineAt=nil end end
        local free=fs.getFreeSpace and fs.getFreeSpace("/");if type(free)=="number"and free<(options.lowSpaceBytes or 50000)then notification("Low storage: "..free.." bytes free","warning",{"monitor"},"device-health")end
        local fuel=turtle and turtle.getFuelLevel and turtle.getFuelLevel();if type(fuel)=="number"and fuel<(options.lowFuel or 100)then notification("Low turtle fuel: "..fuel,"warning",{"monitor"},"device-health")end
        persist();sleep(options.deviceCheckSeconds or 30)
    end end)
    context.supervisor:add("alarm-escalation",function()while true do sleep(10);local now=os.epoch("utc");for _,alarm in pairs(state.alarms)do local pattern=state.alarmPatterns[alarm.pattern]or{};if alarm.status=="active"and#alarm.acknowledgements==0 and not alarm.escalatedAt and now-alarm.startedAt>=((pattern.escalationSeconds or 60)*1000)then alarm.escalatedAt=now;notification("UNACKNOWLEDGED ALARM: "..tostring(alarm.message or alarm.pattern),"emergency",{"monitor","chat","speaker"},"alarm-escalation");publish("alarm.escalated",clone(alarm));persist()end end end end)
    context.supervisor:add("patrol-deadlines",function()while true do sleep(30);local now=os.epoch("utc");for id,route in pairs(state.patrols)do if route.intervalSeconds then local last=route.checks[#route.checks];local due=(last and last.at or route.updatedAt or now)+(route.intervalSeconds*1000);if now>due and(not route.alertedAt or route.alertedAt<due)then route.alertedAt=now;notification("Missed patrol checkpoint: "..id,"warning",{"monitor","chat"},"patrol");publish("patrol.missed",{route=id,dueAt=due});persist()end end end end end)
end

function service.health(context)return context.orchestration~=nil,context.orchestration and"orchestrating"or"not initialized"end
return service
