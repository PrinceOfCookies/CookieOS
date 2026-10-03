return {
    version = 3,
    node = "auth-server-01",
    mode = "server",
    location = "Server Room",
    identity = { nodeKey = "replace-with-the-auth-server-key" },
    network = {
        requireSigned = true,
        trustedKeys = {
            ["command-terminal-01"] = "replace-with-the-terminal-key",
            ["player-tracker-01"] = "replace-with-the-player-tracker-key",
        },
    },
    transports = {
        { name = "facility", side = "back", type = "modem" },
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
    },
    auth = {
        dataPath = "/cookieos-data/users.db",
        importPath = "/subterra_users.txt",
        trustedNodes = {
            ["command-terminal-01"] = "lifeline4603",
        },
        delegates = {
            ["player-tracker-01"] = true,
        },
        seedUsers = {
            lifeline4603 = {
                clearance = 5,
                role = "Site Director",
                status = "Active",
                aliases = { "lifeline", "life" },
                extraPermissions = { "all" },
                password = "change-me-now",
            },
        },
    },
    events = {
        publishers = {
            ["player-tracker-01"] = true,
        },
    },
    pairing = {
        authority = true,
        side = "back",
        codeSeconds = 120,
    },
}
