# CookieOS v3 pairing, updates, and recovery

## Pairing

Run the `pairing` service only on the authority node and set `pairing.authority = true`.
From an authenticated administrator terminal, run `paircode`. On the new computer,
configure a unique `identity.nodeKey`, then run:

```text
pair-node.lua
```

Enter the 16-character code. The request and response are encrypted and authenticated
with that one-time code, which expires after two minutes by default. Both computers
persist the resulting trust data under `/cookieos-data/trust.db`; the code cannot be
reused. Use `revoke <node>` immediately for a lost or retired computer. Re-pairing a
node replaces its key and acts as manual rotation.

CookieOS currently uses symmetric HMAC identities. Full-mesh operation therefore
distributes peer verification keys to paired nodes. Pairing protects keys in transit,
but compromise of a paired node may expose peer keys. Public-key node identities are
still recommended for a future protocol version.

## Updates

Configure `update.signingKey`, then run `cookieos-update.lua` for the default release,
`cookieos-update.lua <branch-or-tag>` for another Git ref, or pass an explicit HTTP
manifest URL. A release
manifest contains a version, signature, and file entries with absolute target paths,
repository-relative source paths, and SHA-256 hashes. The manifest signature covers every field except
the signature itself.

Updates are downloaded into `/cookieos-update/staged`, verified before live files are
touched, and backed up under `/cookieos-update/backup`. Configuration and
`/cookieos-data` targets are rejected. After application, CookieOS must keep networking
alive for ten seconds to mark the boot healthy. More than two unconfirmed boots enter
offline recovery.

## Recovery

Run `recovery.lua` locally at any time. It does not start CookieOS networking and can:

- roll back the last update;
- disable a service through `/cookieos-data/disabled-services.db`;
- re-enable all configured services;
- restore a named `.bak` file after confirmation;
- inspect the runtime log; and
- reboot or exit to CraftOS.

Recovery deliberately has no remote endpoint.
