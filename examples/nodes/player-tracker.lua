return {
    commandAuthority = { required = true, node = "cookiesecurity-command" },
    version = 3,
    node = "player-tracker-01",
    mode = "server",
    location = "Section 1 | Column 1 | Row 6",
    identity = { nodeKey = "replace-with-a-unique-random-node-key" },
    network = {
        requireSigned = true,
        trustedKeys = {
            ["auth-server-01"] = "replace-with-the-auth-server-key",
            ["command-terminal-01"] = "replace-with-the-terminal-key",
        },
    },
    transports = {
        { name = "facility", side = "back", type = "modem" },
    },
    services = {
        "node",
        "player-tracker",
        "maintenance",
    },
}
