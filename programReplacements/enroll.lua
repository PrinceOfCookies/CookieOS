local enrolled = shell.run("/command-enroll.lua")
if not enrolled then printError("Enrollment failed; management shell will not be opened.") end
