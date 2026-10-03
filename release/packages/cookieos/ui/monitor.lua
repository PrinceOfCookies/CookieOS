local ui = {}

function ui.open(options)
    options = options or {}
    local device = options.side and peripheral.wrap(options.side) or peripheral.find("monitor")
    if not device then return nil, "Monitor not found" end
    if device.setTextScale then device.setTextScale(options.textScale or 0.5) end
    return device
end

function ui.clear(device, background)
    device.setBackgroundColor(background or colors.black)
    device.setTextColor(colors.white)
    device.clear()
    device.setCursorPos(1, 1)
end

function ui.trim(value, width)
    value = tostring(value or "")
    if #value <= width then return value end
    if width <= 3 then return value:sub(1, width) end
    return value:sub(1, width - 3) .. "..."
end

function ui.line(device, y, value, foreground, background)
    local width, height = device.getSize()
    if y < 1 or y > height then return end
    device.setCursorPos(1, y)
    device.setBackgroundColor(background or colors.black)
    device.setTextColor(foreground or colors.white)
    device.clearLine()
    device.write(ui.trim(value, width))
end

function ui.center(device, y, value, foreground, background)
    local width = device.getSize()
    value = ui.trim(value, width)
    ui.line(device, y, "", foreground, background)
    device.setCursorPos(math.max(1, math.floor((width - #value) / 2) + 1), y)
    device.write(value)
end

function ui.header(device, title, background)
    ui.center(device, 1, title, colors.white, background or colors.blue)
end

function ui.statusColor(status)
    status = tostring(status or ""):lower()
    if status == "active" or status == "online" or status == "healthy" then return colors.lime end
    if status == "visitor" or status == "warning" then return colors.yellow end
    if status == "fired" or status == "offline" or status == "error" then return colors.red end
    return colors.white
end

return ui
