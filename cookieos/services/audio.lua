local service = {}

service.manifest = {
    name = "audio", version = "3.4.0",
    provides = { "audio.status", "audio.sound", "audio.alarm", "audio.stop" },
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
end

return service
