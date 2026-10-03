local sha256 = {}
local band, bxor, bnot = bit32.band, bit32.bxor, bit32.bnot
local rrotate, rshift = bit32.rrotate, bit32.rshift

local constants = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function add(...)
    local result = 0
    for index = 1, select("#", ...) do result = band(result + select(index, ...), 0xffffffff) end
    return result
end

local function raw(message)
    local bytes = { message:byte(1, -1) }
    local bitLength = #bytes * 8
    table.insert(bytes, 0x80)
    while #bytes % 64 ~= 56 do table.insert(bytes, 0) end
    local wordSize = 2 ^ 32
    local high = math.floor(bitLength / wordSize)
    local low = bitLength % wordSize
    for shift = 24, 0, -8 do table.insert(bytes, band(rshift(high, shift), 0xff)) end
    for shift = 24, 0, -8 do table.insert(bytes, band(rshift(low, shift), 0xff)) end

    local h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
    for offset = 1, #bytes, 64 do
        local w = {}
        for index = 0, 15 do
            local at = offset + index * 4
            w[index] = add(bit32.lshift(bytes[at], 24), bit32.lshift(bytes[at + 1], 16), bit32.lshift(bytes[at + 2], 8), bytes[at + 3])
        end
        for index = 16, 63 do
            local x, y = w[index - 15], w[index - 2]
            local s0 = bxor(rrotate(x, 7), rrotate(x, 18), rshift(x, 3))
            local s1 = bxor(rrotate(y, 17), rrotate(y, 19), rshift(y, 10))
            w[index] = add(w[index - 16], s0, w[index - 7], s1)
        end

        local a, b, c, d, e, f, g, hh = table.unpack(h)
        for index = 0, 63 do
            local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
            local choice = bxor(band(e, f), band(bnot(e), g))
            local t1 = add(hh, s1, choice, constants[index + 1], w[index])
            local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
            local majority = bxor(band(a, b), band(a, c), band(b, c))
            local t2 = add(s0, majority)
            hh, g, f, e, d, c, b, a = g, f, e, add(d, t1), c, b, a, add(t1, t2)
        end
        h = { add(h[1], a), add(h[2], b), add(h[3], c), add(h[4], d), add(h[5], e), add(h[6], f), add(h[7], g), add(h[8], hh) }
    end

    local output = {}
    for _, value in ipairs(h) do
        for shift = 24, 0, -8 do table.insert(output, string.char(band(rshift(value, shift), 0xff))) end
    end
    return table.concat(output)
end

local function toHex(value)
    return (value:gsub(".", function(byte) return string.format("%02x", byte:byte()) end))
end

function sha256.raw(message) return raw(tostring(message or "")) end
function sha256.hex(message) return toHex(sha256.raw(message)) end

function sha256.hmac(key, message)
    key = tostring(key or "")
    if #key > 64 then key = raw(key) end
    key = key .. string.rep("\0", 64 - #key)
    local inner, outer = {}, {}
    for index = 1, 64 do
        local byte = key:byte(index)
        inner[index] = string.char(bxor(byte, 0x36))
        outer[index] = string.char(bxor(byte, 0x5c))
    end
    return toHex(raw(table.concat(outer) .. raw(table.concat(inner) .. tostring(message or ""))))
end

return sha256
