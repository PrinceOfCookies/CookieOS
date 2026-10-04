local installer = assert(loadfile("install.lua"))
installer("--self-test")
local releaseInstaller = assert(loadfile("release/install.lua"))
releaseInstaller("--self-test")
