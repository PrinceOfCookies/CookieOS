local canonical = {}

local function encode(value, seen)
    local kind = type(value)
    if kind == "nil" then return "n" end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "number" then return "d" .. string.format("%.17g", value) .. ";" end
    if kind == "string" then return "s" .. #value .. ":" .. value end
    if kind ~= "table" then error("Cannot sign value of type " .. kind) end
    if seen[value] then error("Cannot sign cyclic table") end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do table.insert(keys, key) end
    table.sort(keys, function(left, right)
        local a, b = type(left) .. ":" .. tostring(left), type(right) .. ":" .. tostring(right)
        return a < b
    end)
    local parts = { "t", tostring(#keys), ":" }
    for _, key in ipairs(keys) do
        table.insert(parts, encode(key, seen))
        table.insert(parts, encode(value[key], seen))
    end
    seen[value] = nil
    return table.concat(parts)
end

function canonical.encode(value) return encode(value, {}) end

return canonical
