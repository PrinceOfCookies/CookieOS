return {
    version = 3,
    node = "cookiesecurity-core-01",
    mode = "hybrid",
    location = "Server Room",
    commandAuthority = { required = true, node = "cookiesecurity-command" },

    transports = {
        { name = "facility", side = "back", type = "modem" },
        { name = "wired", side = "bottom", type = "modem" },
    },

    services = {
        "node",
        "auth",
        "audit",
        "events",
        "personnel",
        "security",
        "maintenance",
        "pairing",
        "terminal",
    },
    pairing = { authority = true, side = "back", codeSeconds = 120 },

    auth = {
        dataPath = "/cookieos-data/users.db",
        trustedNodes = {
            ["command-terminal-01"] = "lifeline4603",
        },
        seedUsers = {
            lifeline4603 = {
                clearance = 5, role = "Site Director", status = "Active",
                aliases = { "lifeline", "life" }, extraPermissions = { "all" },
                password = "change-me-now",
            },
        },
    },
}
