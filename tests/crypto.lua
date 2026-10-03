package.path = package.path .. ";/?.lua;/?/init.lua"

local Sha256 = require("cookieos.crypto.sha256")
local Canonical = require("cookieos.crypto.canonical")
local Box = require("cookieos.crypto.box")
local Update = require("cookieos.update")

assert(Sha256.hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
assert(Sha256.hmac("key", "The quick brown fox jumps over the lazy dog") == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
assert(Canonical.encode({ b = 2, a = 1 }) == Canonical.encode({ a = 1, b = 2 }))
local sealed = Box.seal("pairing-code", "node secret", "fixed-nonce")
assert(Box.open("pairing-code", sealed) == "node secret")
sealed.cipher = sealed.cipher:sub(1, -2) .. (sealed.cipher:sub(-1) == "0" and "1" or "0")
assert(Box.open("pairing-code", sealed) == nil)

local manifest = { version = "3.4.0", files = {{ path = "/cookieos/runtime.lua", sha256 = Sha256.hex("content") }} }
manifest.signature = Sha256.hmac("release-key", Canonical.encode(manifest))
assert(Update.verifyManifest(manifest, "release-key"))
manifest.version = "tampered"
assert(Update.verifyManifest(manifest, "release-key") == nil)

print("All 7 crypto and release tests passed")
