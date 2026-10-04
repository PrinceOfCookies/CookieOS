# CookieOS
- A custom "OS" for Computercraft

## Installation

Use the single guided `install.lua` for fresh installs, upgrades, repairs,
reconfiguration, offline disks, recovery, and uninstall. See the
[installation guide](docs/installation.md).

Because the GitHub API returns base64 JSON, download and decode the installer once:

```lua
lua
local r=assert(http.get("https://api.github.com/repos/PrinceOfCookies/CookieOS/contents/release/install.lua?ref=cookieos-v3-rewrite",{["User-Agent"]="CookieOS"}));local j=textutils.unserializeJSON(r.readAll());r.close();local o=fs.open("install.lua","w");o.write(textutils.decodeBase64(j.content:gsub("%s","")));o.close()
exit()
install.lua
```

## CookieOS v3 preview

The repository now contains an opt-in distributed runtime for client, server,
relay, and hybrid computers. It includes service discovery, addressed requests and
responses, loop-safe relaying, and supervised tasks. Start with
[the v3 quick start](docs/v3-quickstart.md) and read
[the architecture](docs/v3-architecture.md).

Native authorization, user provisioning, and trusted terminal configuration are
covered in [the v3 authentication guide](docs/v3-auth.md).
Service packaging and dependency declarations are described in
[the service manifest guide](docs/v3-services.md).
Operational limits, auditing, delegated authorization, tracking, and diagnostics are
covered in [the operations guide](docs/v3-operations.md).
Personnel queries, domain events, and monitor components are documented in
[the events and personnel guide](docs/v3-events-personnel.md).
Node enrollment, staged upgrades, rollback, and offline repair are covered in
[the deployment guide](docs/v3-deployment.md).

## Notes
- This is not really meant to be used by anyone other than me, but if you want to.. go for it
- If you modify any system files, and it ends up breaking, I probably wont help you with issues reguardign it
- If you'd like to contribute, feel free to make a PR
- If you find any bugs, please repot them in the issues tab
