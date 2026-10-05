# CookieOS v4 rewrite

The `cookieos-v4-rewrite` branch is a clean-break rewrite. The v3 branch remains
the rollback release while v4 is developed.

## Boundaries

- `kernel`: boot, services, supervision, and fail-closed startup
- `identity`: one account/session model for Auth terminals and Command Authority
- `transport`: signed requests, optional logger hop, discovery, and relays
- `policy`: clearance, permissions, lockdown, and audit decisions
- `ui`: normal terminal, Command shell, monitor output, chat, and notifications
- `release`: one self-contained installer with API downloads, staging, hashes,
  signatures, rollback, and offline bundle support

V4 will not silently migrate an existing v3 database. The installer will create a
versioned backup, import only explicitly supported identity and trust records, and
leave the v3 installation recoverable until the first successful v4 boot.

## Compatibility rules

The runtime will continue to support CC:Tweaked's Lua 5.2/5.3 environments,
yield during hashing and network staging, close every HTTP handle, and use the
GitHub Contents API rather than `raw.githubusercontent.com`.

Command Authority remains the only CL6 unrestricted shell. Ordinary terminals
must authenticate through Auth and never fall back to CraftOS when enrollment or
authorization fails.
