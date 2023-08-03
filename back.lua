os.loadAPI("apis/cUtils.lua")

cUtils.logToOS("[M:02] Navigating from " .. shell.getRunningProgram() .. " to ios/.menu at " .. cUtils.getTime())

shell.run("ios/.menu")