# CookieOS v3 authentication

Add `auth` before or after other services in the node configuration; the runtime
always initializes it first. On first boot it checks `auth.dataPath`, imports a
legacy `subterra_users.txt` when present, or creates the database from `seedUsers`.

```lua
auth = {
  dataPath = "/cookieos-data/users.db",
  importPath = "/subterra_users.txt",
  trustedNodes = {
    ["command-terminal-01"] = "lifeline4603",
  },
  seedUsers = {
    lifeline4603 = {
      clearance = 5,
      role = "Site Director",
      status = "Active",
      extraPermissions = { "all" },
    },
  },
}
```

`trustedNodes` binds a configured node name to the user it may act as. `"*"` allows
that node to supply any actor and should only be used temporarily during migration.
This mapping alone only prevents accidental impersonation. Enable signed networking
for an actual node identity boundary; sessions on an unsigned network remain a
migration feature, not a secure deployment.

Users can open short-lived sessions with `login`. Sessions are bound to the
requesting node, expire after `auth.sessionSeconds`, and are revoked when the user's
credential changes. Five failed logins trigger a temporary lock by default. Imported
legacy users do not initially have credentials; an authorized trusted terminal can
bootstrap one with `passwd <user>`, then switch to session-based access.

Login uses a short-lived nonce challenge and an HMAC proof derived from the stored
password verifier. The password itself is never transmitted over the modem.

Passwords are stored as salted, iterated SHA-256 values, never plaintext. The
iteration count is intentionally modest for ComputerCraft hardware, so use long,
unique passwords and protect the database backup.

The database keeps its previous version as `users.db.bak` during updates. Native
services are `auth.check`, `auth.whois`, `auth.users.list`, `auth.user.set`,
`auth.user.remove`, `auth.permission.add`, `auth.permission.remove`, credential
management, login, validation, and logout.

For legacy migration, `legacy.trustActors = true` permits old SubTerra management
packets to retain their actor field. Disable the legacy gateway, or at minimum this
option, as soon as old command nodes have migrated.

Run the CC-side protocol checks with:

```text
tests/network.lua
tests/auth.lua
tests/crypto.lua
```
