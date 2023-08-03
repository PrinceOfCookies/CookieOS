os.pullEvent = os.pullEventRaw
shell.run("cd /")
os.loadAPI("apis/cUtils.lua")

cUtils.tSetTextColor(colors.white)
cUtils.tClear()
cUtils.tSetCursorPos(1, 1)

local x, _ = cUtils.tGetSize()

print("Welcome to our cmd prompt")
print("Type 'chelp' for a list of commands")
print("To return to main menu, type `back`")
print(string.rep("=", x - 1))