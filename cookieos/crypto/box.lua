local Sha256 = require("cookieos.crypto.sha256")
local box = {}

local function hexToRaw(value)
    return (value:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
end

local function rawToHex(value)
    return (value:gsub(".", function(byte) return string.format("%02x", byte:byte()) end))
end

local function crypt(key, nonce, input)
    local output, offset, counter = {}, 1, 0
    while offset <= #input do
        counter = counter + 1
        local stream = hexToRaw(Sha256.hmac(key, "stream:" .. nonce .. ":" .. counter))
        local chunk = input:sub(offset, offset + #stream - 1)
        local encoded = {}
        for index = 1, #chunk do encoded[index] = string.char(bit32.bxor(chunk:byte(index), stream:byte(index))) end
        table.insert(output, table.concat(encoded))
        offset = offset + #stream
    end
    return table.concat(output)
end

function box.seal(key, plaintext, nonce)
    nonce = nonce or Sha256.hex(tostring(os.epoch("utc")) .. ":" .. tostring(math.random()) .. ":" .. tostring(math.random())):sub(1, 32)
    local cipher = rawToHex(crypt(tostring(key), nonce, tostring(plaintext)))
    return { nonce = nonce, cipher = cipher, tag = Sha256.hmac(key, "tag:" .. nonce .. ":" .. cipher) }
end

function box.open(key, sealed)
    if type(sealed) ~= "table" or type(sealed.nonce) ~= "string" or type(sealed.cipher) ~= "string" then
        return nil, "Invalid sealed payload"
    end
    local expected = Sha256.hmac(key, "tag:" .. sealed.nonce .. ":" .. sealed.cipher)
    if expected ~= sealed.tag then return nil, "Pairing payload authentication failed" end
    return crypt(tostring(key), sealed.nonce, hexToRaw(sealed.cipher))
end

return box
