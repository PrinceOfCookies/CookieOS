local args = { ... }
local target = shell.resolve(args[1] or ".")
local showHidden, details = false, false
for _, argument in ipairs(args) do if argument == "-a" then showHidden = true elseif argument == "-l" then details = true end end
if not fs.exists(target) then return printError("Path not found: " .. target) end
if not fs.isDir(target) then
    local attributes = fs.attributes(target)
    print(string.format("%s  %d bytes%s", target, attributes.size or 0, attributes.isReadOnly and "  read-only" or "")); return
end
local entries = fs.list(target); table.sort(entries, function(a,b)return a:lower()<b:lower()end)
for _, name in ipairs(entries) do
    if showHidden or name:sub(1,1) ~= "." then
        local path = fs.combine(target,name); local directory = fs.isDir(path)
        term.setTextColor(directory and colors.lightBlue or colors.white)
        if details then local size = directory and "<DIR>" or tostring(fs.getSize(path)); print(string.format("%-8s %s",size,name)) else print((directory and "["..name.."]" or name)) end
    end
end
term.setTextColor(colors.white)
