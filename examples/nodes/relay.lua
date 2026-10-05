return {
    commandAuthority = { required = true, node = "cookiesecurity-command" },
    version = 3,
    node = "facility-relay-01",
    mode = "relay",
    location = "Relay Closet",
    transports = {
        { name = "upstream", side = "back", type = "modem" },
        { name = "downstream", side = "front", type = "modem" },
    },
    services = { "node" },
}
