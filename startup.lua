os.loadAPI("apis/cUtils.lua")

cUtils.tClear()
cUtils.tSetCursorPos(1, 1)
cUtils.tSetTextColor(colors.yellow)
print("CookieOS 1.0.0")

cUtils.tSetTextColor(colors.white)
cUtils.slowPrint("Loading...")

cUtils.tSetCursorPos(1, 3)
cUtils.sleep(1)
cUtils.slowPrint("##############")
cUtils.sleep(1)
shell.run("ios/.menu")