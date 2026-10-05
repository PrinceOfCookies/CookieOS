local path=({...})[1]or"/cookieos-data/runtime.log";if not fs.exists(path)then return printError("Log not found: "..path)end;shell.run("edit",path)
