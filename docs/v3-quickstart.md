# CookieOS v3 quick start

Copy the repository to the ComputerCraft computer, then copy one example node file:

```text
copy examples/nodes/hybrid.lua cookieos-node.lua
startup-v3
```

Adjust the node name, location, modem sides, and mode before deployment. To make v3
the default after testing, create a root `startup.lua` containing:

```lua
shell.run("startup-v3.lua")
```

Do not replace the existing startup path until the node has successfully joined the
network. Runtime messages are written to `/cookieos-data/runtime.log`.

Install the Command Authority before using the dedicated Auth example. Physically
authenticate at Command and run `command-enroll`, then enroll the Auth node with the
one-use code before its first boot.

For a two-segment relay, start from `examples/nodes/relay.lua`. Modems on both sides
must be present before boot; a missing configured modem intentionally fails the
network task and is retried by the supervisor.
