-- SPDX-FileCopyrightText: 2017 Daniel Ratcliffe
--
-- SPDX-License-Identifier: LicenseRef-CCPL

term.setTextColor(colors.yellow)
local main, co = os.version()

print("Main load: " .. main)
print("Co-load: " .. co)