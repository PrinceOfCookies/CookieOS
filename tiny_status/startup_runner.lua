-- startup.lua
-- Runs your main script and the tiny top monitor status script together.
-- Rename your current startup.lua to main_startup.lua, then use this as startup.lua.

local function runFile(path)
  local fn, err = loadfile(path)

  if not fn then
    error("Failed to load " .. path .. ": " .. tostring(err))
  end

  fn()
end

local function runMain()
  runFile("main_startup.lua")
end

local function runTinyStatus()
  runFile("tiny_status.lua")
end

parallel.waitForAll(runMain, runTinyStatus)
