# Installing CookieOS

CookieOS now uses one self-contained `install.lua`. A release can publish it for:

```lua
wget run https://example.invalid/cookieos/install.lua
```

Running without arguments opens the hardware-aware role wizard. It detects attached
modems, monitors, and service-specific peripherals, then generates
`/cookieos-node.lua`. Existing configuration is backed up and cryptographic identity,
trust, Auth, event, and update settings are preserved during reconfiguration.

## Modes

```text
install.lua
install.lua --role relay
install.lua --version v3.4.0
install.lua --manifest https://host/manifest.json
install.lua --offline disk
install.lua --upgrade
install.lua --repair
install.lua --reconfigure
install.lua --recovery
install.lua --uninstall
install.lua --self-test
```

`--upgrade` and `--repair` preserve the current node configuration. Repair performs a
fresh manifest-verified installation. Reconfiguration only rewrites configuration.
Uninstall restores the previous `startup.lua` and asks separately before removing
configuration or `/cookieos-data`.

## Installation transaction

The installer verifies the release manifest, downloads every file into
`/cookieos-install/staged`, checks its SHA-256 hash, backs up existing targets, and
only then replaces live files. A failure during replacement restores completed
targets. The installed manifest is retained for upgrades and clean removal.

Configuration, trust databases, and service data cannot be release targets. The
generated `startup.lua` enters the existing update health/recovery workflow.

## Offline disk

An offline release has this structure:

```text
disk/
  install.lua
  manifest.json
  packages/
```

Run `disk/install.lua --offline disk`. No external JSON library or HTTP connection is
required.

## Building releases

From the repository:

```text
node tools/build-release.mjs 3.4.0 https://downloads.example/cookieos RELEASE_KEY
```

The builder creates `dist/release` with the online/offline package tree, hashes,
authenticated manifest, and a single installer containing the matching release key.
The current release authentication uses symmetric HMAC, so distributing that embedded
key permits verification but cannot provide publisher-only signatures. Treat it as
tamper detection until the release format moves to public-key signatures.
