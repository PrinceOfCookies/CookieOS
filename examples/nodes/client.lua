return {
    version = 3,
    node = "command-terminal-01",
    mode = "client",
    location = "Command Center",
    identity = {
        user = "lifeline4603",
        nodeKey = "replace-with-the-terminal-key",
    },
    network = {
        requireSigned = true,
        trustedKeys = {
            ["auth-server-01"] = "replace-with-the-auth-server-key",
            ["player-tracker-01"] = "replace-with-the-player-tracker-key",
        },
    },
    transports = {
        { name = "facility", side = "back", type = "modem" },
    },
    services = {
        "node",
        "terminal",
    },
}
