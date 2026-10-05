local Sha256 = require("cookieos.crypto.sha256")
local identity = {}

function identity.credential(node, password, salt)
    salt = salt or Sha256.hex(tostring(node) .. ":" .. tostring(os.epoch("utc"))):sub(1, 32)
    local value = salt .. ":" .. tostring(password)
    for _ = 1, 64 do value = Sha256.hex(value .. ":" .. salt) end
    return { salt = salt, rounds = 64, hash = value }
end

function identity.verify(credential, password)
    if type(credential) ~= "table" or type(credential.salt) ~= "string" then return false end
    local value = credential.salt .. ":" .. tostring(password)
    for _ = 1, tonumber(credential.rounds) or 64 do value = Sha256.hex(value .. ":" .. credential.salt) end
    return value == credential.hash
end

return identity
