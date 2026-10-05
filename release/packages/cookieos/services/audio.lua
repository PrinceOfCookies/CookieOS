local service = {}

service.manifest = {
    name = "audio", version = "3.4.0",
    provides = { "audio.status", "audio.sound", "audio.alarm", "audio.stop", "audio.announce" },
    depends = { "node" }, peripherals = { "speaker" },
}

function service.register(context)
    local speakers = { peripheral.find("speaker") }
    if #speakers == 0 then error("audio service requires a speaker") end

    local function authorize(payload, packet, permission)
        local allowed, reason = context.authorize(payload, packet, permission)
        if not allowed then return nil, reason end
        return true
    end

    context.network:provide("audio.status", function(payload, packet)
        local ok, err = authorize(payload, packet, "audio.trigger")
        if not ok then return nil, err end
        return { speakers = #speakers, zone = (context.config.audio or {}).zone or context.config.location }
    end)

    context.network:provide("audio.sound", function(payload, packet)
        local ok, err = authorize(payload, packet, "audio.trigger")
        if not ok then return nil, err end
        local sound = tostring(payload.sound or "minecraft:block.note_block.pling")
        local volume = math.max(0, math.min(3, tonumber(payload.volume) or 1))
        local pitch = math.max(0.5, math.min(2, tonumber(payload.pitch) or 1))
        for _, speaker in ipairs(speakers) do speaker.playSound(sound, volume, pitch) end
        return { sound = sound, zone = (context.config.audio or {}).zone or context.config.location }
    end)

    context.network:provide("audio.alarm", function(payload, packet)
        local ok, err = authorize(payload, packet, "audio.trigger")
        if not ok then return nil, err end
        local count = math.max(1, math.min(10, tonumber(payload.count) or 3))
        for _ = 1, count do
            for _, speaker in ipairs(speakers) do speaker.playSound("minecraft:block.bell.use", 2, 0.7) end
            sleep(0.35)
        end
        return { alarm = true, count = count }
    end)

    context.network:provide("audio.stop", function(payload, packet)
        local ok, err = authorize(payload, packet, "audio.stop")
        if not ok then return nil, err end
        for _, speaker in ipairs(speakers) do speaker.stop() end
        return { stopped = true }
    end)

    context.network:provide("audio.announce", function(payload, packet)
        local ok, err = authorize(payload, packet, "announcements.send")
        if not ok then return nil, err end
        local message = tostring(payload.message or "")
        if message == "" or #message > 240 then return nil, "Announcement must contain 1-240 characters" end
        local priority = tostring(payload.priority or "normal"):lower()
        local cues = { normal = { "minecraft:block.note_block.pling", 1.2 }, urgent = { "minecraft:block.bell.use", 0.8 }, emergency = { "minecraft:entity.wither.spawn", 1 } }
        local cue = cues[priority]; if not cue then return nil, "Priority must be normal, urgent, or emergency" end
        for _, speaker in ipairs(speakers) do speaker.playSound(cue[1], priority == "emergency" and 3 or 2, cue[2]) end
        -- CC speakers cannot synthesize arbitrary text; monitors/chat gateways consume this event.
        context.publish("announcement", { message = message, priority = priority, zone = (context.config.audio or {}).zone or context.config.location })
        return { announced = true, message = message, priority = priority, zone = (context.config.audio or {}).zone or context.config.location }
    end)
end

return service
