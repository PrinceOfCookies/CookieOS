return {
    version = 3,
    node = "subterra-core-01",
    mode = "hybrid",
    location = "Server Room",

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
    },

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
