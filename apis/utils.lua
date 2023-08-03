--[[ UTILS ]]
-- technically it makes everything slower but also makes more compatible with other Lua based stuff
-- Computercraft uses a bit api instead of operators (~, &, |) so it"s a bit slower
-- OpenComputers should have support for bit operators afaik
local bitXor = bit.bxor
local bitAnd = bit.band
local bitOr = bit.bor
local bitNot = bit.bnot
local bitShiftLeft = bit.blshift
local bitShiftRight = bit.brshift
local spack, sunpack = string.pack, string.unpack

--[[ MD5 ]]
------------------------------------------------------------------------
-- md5 hash - see RFC 1321 - https://www.ietf.org/rfc/rfc1321.txt
local function FF(a, b, c, d, x, s, ac)
    a = bitAnd(a + bitOr(bitAnd(b, c), bitAnd(bitNot(b), d)) + x + ac, 0xffffffff)
    a = bitAnd(bitOr(bitShiftLeft(a, s), bitShiftRight(a, 32 - s)), 0xffffffff)
    a = bitAnd(a + b, 0xffffffff)

    return a
end

local function GG(a, b, c, d, x, s, ac)
    a = bitAnd(a + bitOr(bitAnd(b, d), bitAnd(c, bitNot(d))) + x + ac, 0xffffffff)
    a = bitAnd(bitOr(bitShiftLeft(a, s), bitShiftRight(a, 32 - s)), 0xffffffff)
    a = bitAnd(a + b, 0xffffffff)

    return a
end

local function HH(a, b, c, d, x, s, ac)
    a = bitAnd(a + bitXor(bitXor(b, c), d) + x + ac, 0xffffffff)
    a = bitAnd(bitOr(bitShiftLeft(a, s), bitShiftRight(a, 32 - s)), 0xffffffff)
    a = bitAnd(a + b, 0xffffffff)

    return a
end

local function II(a, b, c, d, x, s, ac)
    a = bitAnd(a + bitXor(c, bitOr(b, bitNot(d))) + x + ac, 0xffffffff)
    a = bitAnd(bitOr(bitShiftLeft(a, s), bitShiftRight(a, 32 - s)), 0xffffffff)
    a = bitAnd(a + b, 0xffffffff)

    return a
end

local function transform(state, input, i, t)
    -- process the 64-byte input block in string "input" at offset "i"
    -- t is a uint32[16] array. It is passed as a parameter
    -- for performance reasons
    --
    local a, b, c, d = state[1], state[2], state[3], state[4]

    -- load array
    for j = 1, 16 do
        t[j] = sunpack("<I4", input, i)
        i = i + 4
    end

    -- Round 1
    a = FF(a, b, c, d, t[1], 7, 0xd76aa478)
    d = FF(d, a, b, c, t[2], 12, 0xe8c7b756)
    c = FF(c, d, a, b, t[3], 17, 0x242070db)
    b = FF(b, c, d, a, t[4], 22, 0xc1bdceee)
    a = FF(a, b, c, d, t[5], 7, 0xf57c0faf)
    d = FF(d, a, b, c, t[6], 12, 0x4787c62a)
    c = FF(c, d, a, b, t[7], 17, 0xa8304613)
    b = FF(b, c, d, a, t[8], 22, 0xfd469501)
    a = FF(a, b, c, d, t[9], 7, 0x698098d8)
    d = FF(d, a, b, c, t[10], 12, 0x8b44f7af)
    c = FF(c, d, a, b, t[11], 17, 0xffff5bb1)
    b = FF(b, c, d, a, t[12], 22, 0x895cd7be)
    a = FF(a, b, c, d, t[13], 7, 0x6b901122)
    d = FF(d, a, b, c, t[14], 12, 0xfd987193)
    c = FF(c, d, a, b, t[15], 17, 0xa679438e)
    b = FF(b, c, d, a, t[16], 22, 0x49b40821)
    -- Round 2
    a = GG(a, b, c, d, t[2], 5, 0xf61e2562)
    d = GG(d, a, b, c, t[7], 9, 0xc040b340)
    c = GG(c, d, a, b, t[12], 14, 0x265e5a51)
    b = GG(b, c, d, a, t[1], 20, 0xe9b6c7aa)
    a = GG(a, b, c, d, t[6], 5, 0xd62f105d)
    d = GG(d, a, b, c, t[11], 9, 0x2441453)
    c = GG(c, d, a, b, t[16], 14, 0xd8a1e681)
    b = GG(b, c, d, a, t[5], 20, 0xe7d3fbc8)
    a = GG(a, b, c, d, t[10], 5, 0x21e1cde6)
    d = GG(d, a, b, c, t[15], 9, 0xc33707d6)
    c = GG(c, d, a, b, t[4], 14, 0xf4d50d87)
    b = GG(b, c, d, a, t[9], 20, 0x455a14ed)
    a = GG(a, b, c, d, t[14], 5, 0xa9e3e905)
    d = GG(d, a, b, c, t[3], 9, 0xfcefa3f8)
    c = GG(c, d, a, b, t[8], 14, 0x676f02d9)
    b = GG(b, c, d, a, t[13], 20, 0x8d2a4c8a)
    -- Round 3
    a = HH(a, b, c, d, t[6], 4, 0xfffa3942)
    d = HH(d, a, b, c, t[9], 11, 0x8771f681)
    c = HH(c, d, a, b, t[12], 16, 0x6d9d6122)
    b = HH(b, c, d, a, t[15], 23, 0xfde5380c)
    a = HH(a, b, c, d, t[2], 4, 0xa4beea44)
    d = HH(d, a, b, c, t[5], 11, 0x4bdecfa9)
    c = HH(c, d, a, b, t[8], 16, 0xf6bb4b60)
    b = HH(b, c, d, a, t[11], 23, 0xbebfbc70)
    a = HH(a, b, c, d, t[14], 4, 0x289b7ec6)
    d = HH(d, a, b, c, t[1], 11, 0xeaa127fa)
    c = HH(c, d, a, b, t[4], 16, 0xd4ef3085)
    b = HH(b, c, d, a, t[7], 23, 0x4881d05)
    a = HH(a, b, c, d, t[10], 4, 0xd9d4d039)
    d = HH(d, a, b, c, t[13], 11, 0xe6db99e5)
    c = HH(c, d, a, b, t[16], 16, 0x1fa27cf8)
    b = HH(b, c, d, a, t[3], 23, 0xc4ac5665)
    -- Round 4
    a = II(a, b, c, d, t[1], 6, 0xf4292244)
    d = II(d, a, b, c, t[8], 10, 0x432aff97)
    c = II(c, d, a, b, t[15], 15, 0xab9423a7)
    b = II(b, c, d, a, t[6], 21, 0xfc93a039)
    a = II(a, b, c, d, t[13], 6, 0x655b59c3)
    d = II(d, a, b, c, t[4], 10, 0x8f0ccc92)
    c = II(c, d, a, b, t[11], 15, 0xffeff47d)
    b = II(b, c, d, a, t[2], 21, 0x85845dd1)
    a = II(a, b, c, d, t[9], 6, 0x6fa87e4f)
    d = II(d, a, b, c, t[16], 10, 0xfe2ce6e0)
    c = II(c, d, a, b, t[7], 15, 0xa3014314)
    b = II(b, c, d, a, t[14], 21, 0x4e0811a1)
    a = II(a, b, c, d, t[5], 6, 0xf7537e82)
    d = II(d, a, b, c, t[12], 10, 0xbd3af235)
    c = II(c, d, a, b, t[3], 15, 0x2ad7d2bb)
    b = II(b, c, d, a, t[10], 21, 0xeb86d391)
    state[1] = bitAnd(state[1] + a, 0xffffffff)
    state[2] = bitAnd(state[2] + b, 0xffffffff)
    state[3] = bitAnd(state[3] + c, 0xffffffff)
    state[4] = bitAnd(state[4] + d, 0xffffffff)
end

--transform()
local function md5(input)
    -- initialize state
    local state = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476}

    local inputlen = #input
    local inputbits = inputlen * 8 -- input length in bits
    local r = inputlen -- number of unprocessed bytes
    local i = 1 -- index in input string

    -- input block uint32[16]
    local ibt = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

    -- process as many 64-byte blocks as possible
    while r >= 64 do
        -- process block
        transform(state, input, i, ibt)
        i = i + 64 -- update input index
        r = r - 64 -- update number of unprocessed bytes
    end

    -- finalize.  must append to input a mandatory 0x80 byte, some
    --  padding, and the input bit-length ("inputbits")
    local lastblock -- the rest of input .. some padding .. inputbits
    local padlen -- padding length in bytes

    if r < 56 then
        padlen = 55 - r
    else
        padlen = 119 - r
    end

    lastblock = input:sub(i) .. "\x80" .. ("\0"):rep(padlen) .. spack("<I8", inputbits) -- remaining input --padding -- length in bits
    assert(#lastblock == 64 or #lastblock == 128)
    transform(state, lastblock, 1, ibt)

    if #lastblock == 128 then
        transform(state, lastblock, 65, ibt)
    end

    -- return the digest
    local digest = spack("<I4I4I4I4", state[1], state[2], state[3], state[4])

    return digest
end

--md5()
--[[ rc4 encryption / decryption ]]
local byte, char, concat = string.byte, string.char, table.concat

local function keysched(key)
    -- key must be a 16-byte string
    assert(#key == 16, "key must be a 16-byte string")
    local s = {}
    local j, ii, jj

    for i = 0, 255 do
        s[i + 1] = i
    end

    j = 0

    for i = 0, 255 do
        ii = i + 1
        j = bitAnd(j + s[ii] + byte(key, (i % 16) + 1), 0xff)
        jj = j + 1
        s[ii], s[jj] = s[jj], s[ii]
    end

    return s
end

local function step(s, i, j)
    i = bitAnd(i + 1, 0xff)
    local ii = i + 1
    j = bitAnd(j + s[ii], 0xff)
    local jj = j + 1
    s[ii], s[jj] = s[jj], s[ii]
    local k = s[bitAnd(s[ii] + s[jj], 0xff) + 1]

    return s, i, j, k
end

local function rc4raw(key, plain)
    -- raw encryption
    -- key must be a 16-byte string
    local s = keysched(key)
    local i, j = 0, 0
    local k
    local t = {}

    for n = 1, #plain do
        s, i, j, k = step(s, i, j)
        t[n] = char(bitXor(byte(plain, n), k))
    end

    return concat(t)
end

local function rc4(key, plain, drop)
    -- encrypt "plain", return encrypted text
    -- key must be a 16-byte string
    -- optional drop (default = 256): ignore first "drop" iterations
    drop = drop or 256
    local s = keysched(key)
    local i, j = 0, 0
    local k
    local t = {}

    -- run and ignore "drop" iterations
    for _ = 1, drop do
        s, i, j = step(s, i, j)
    end

    -- now start to encrypt
    for n = 1, #plain do
        s, i, j, k = step(s, i, j)
        t[n] = char(bitXor(byte(plain, n), k))
    end

    return concat(t)
end

--[[ COMPRESSION ]]
local char = string.char
local type = type
local select = select
local sub = string.sub
local tconcat = table.concat
local basedictcompress = {}
local basedictdecompress = {}

for i = 0, 255 do
    local ic, iic = char(i), char(i, 0)
    basedictcompress[ic] = iic
    basedictdecompress[iic] = ic
end

local function dictAddA(str, dict, a, b)
    if a >= 256 then
        a, b = 0, b + 1

        if b >= 256 then
            dict = {}
            b = 1
        end
    end

    dict[str] = char(a, b)
    a = a + 1

    return dict, a, b
end

function compress(input, ignoreSize)
    if type(input) ~= "string" then return nil, "string expected, got " .. type(input) end
    local len = #input
    if len <= 1 then return "u" .. input end
    local dict = {}
    local a, b = 0, 1

    local result = {"c"}

    local resultlen = 1
    local n = 2
    local word = ""

    for i = 1, len do
        local c = sub(input, i, i)
        local wc = word .. c

        if not (basedictcompress[wc] or dict[wc]) then
            local write = basedictcompress[word] or dict[word]
            if not write then return nil, "algorithm error, could not fetch word" end
            result[n] = write
            resultlen = resultlen + #write
            n = n + 1
            if len <= resultlen and ignoreSize ~= true then return "u" .. input end
            dict, a, b = dictAddA(wc, dict, a, b)
            word = c
        else
            word = wc
        end
    end

    result[n] = basedictcompress[word] or dict[word]
    resultlen = resultlen + #result[n]
    n = n + 1
    if len <= resultlen and ignoreSize ~= true then return "u" .. input end

    return tconcat(result)
end

local function dictAddB(str, dict, a, b)
    if a >= 256 then
        a, b = 0, b + 1

        if b >= 256 then
            dict = {}
            b = 1
        end
    end

    dict[char(a, b)] = str
    a = a + 1

    return dict, a, b
end

function decompress(input)
    if type(input) ~= "string" then return nil, "string expected, got " .. type(input) end
    if #input < 1 then return nil, "invalid input - not a compressed string" end
    local control = sub(input, 1, 1)

    if control == "u" then
        return sub(input, 2)
    elseif control ~= "c" then
        return nil, "invalid input - not a compressed string"
    end

    input = sub(input, 2)
    local len = #input
    if len < 2 then return nil, "invalid input - not a compressed string" end
    local dict = {}
    local a, b = 0, 1
    local result = {}
    local n = 1
    local last = sub(input, 1, 2)
    result[n] = basedictdecompress[last] or dict[last]
    n = n + 1

    for i = 3, len, 2 do
        local code = sub(input, i, i + 1)
        local lastStr = basedictdecompress[last] or dict[last]
        if not lastStr then return nil, "could not find last from dict. Invalid input?" end
        local toAdd = basedictdecompress[code] or dict[code]

        if toAdd then
            result[n] = toAdd
            n = n + 1
            dict, a, b = dictAddB(lastStr .. sub(toAdd, 1, 1), dict, a, b)
        else
            local tmp = lastStr .. sub(lastStr, 1, 1)
            result[n] = tmp
            n = n + 1
            dict, a, b = dictAddB(tmp, dict, a, b)
        end

        last = code
    end

    return tconcat(result)
end

function fromhex(str)
    return str:gsub("..", function(cc) return string.char(tonumber(cc, 16)) end)
end

function tohex(str)
    return str:gsub(".", function(c) return string.format("%02X", string.byte(c)) end)
end

--[[
    Steps:
    1. Encrypt the plaintext with RC4
    2. Compress the plaintext with LZW
    3. Attach MD5 hash of Compressed data to the compressed data
    4. Return the compressed data
]]
function Package(KEY, data)
    if type(KEY) ~= "string" then return nil, "string expected, got " .. type(KEY) end
    local encryptedData = rc4(KEY, data) -- encrypt data
    local compressedData = compress(encryptedData) -- compress data
    compressedData = compressedData .. md5(KEY .. compressedData) -- add md5 hash to compressed data to verify integrity

    return compressedData
end

--[[
    Steps:
    1. Decompress the compressed data
    2. Decrypt the decompressed data
    3. Verify the integrity of the data
    4. Return the decompressed data
]]
function UnPackage(KEY, encryptedData)
    local compressedData = sub(encryptedData, 1, -17) -- get compressed data without md5 hash
    local md5Hash = sub(encryptedData, -16) -- get md5 hash of compressed data
    if md5(KEY .. compressedData) ~= md5Hash then return nil, "invalid data - integrity check failed" end -- verify integrity of compressed data
    local decompressedData = decompress(compressedData) -- decompress data
    if not decompressedData then return nil, "invalid data - decompression failed" end
    local decryptedData = rc4(KEY, decompressedData) -- decrypt data

    return decryptedData
end

-- Globals for Computercraft
if os and os.version then
    Compress = compress
    Decompress = decompress
    Encrypt = rc4
    Decrypt = rc4
    MD5 = md5
end


--[[
    Usage:
        compress(data [string], disableSizeCheck [bool] ):
            Tries to compress the given data. if disableSizeCheck is true it wont bother
            with the size before and after compression.
            
        decompress(data [string]):
            Decompresses data
        
        rc4(key, plain, drop):
            Encrypts plain with the given key. drop is the number of iterations to ignore.
            Also Decrypts data the same way.
            Secure enough for minecraft i guess
]]