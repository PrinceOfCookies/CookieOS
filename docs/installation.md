# Installing CookieOS

CookieOS uses one self-contained `install.lua`. Bootstrap it through GitHub's Contents
API, which returns base64-encoded JSON:

```lua
lua
local r=assert(http.get("https://api.github.com/repos/PrinceOfCookies/CookieOS/contents/release/install.lua?ref=cookieos-v3-rewrite",{["User-Agent"]="CookieOS"}));local j=textutils.unserializeJSON(r.readAll());r.close();local o=fs.open("install.lua","w");o.write(textutils.decodeBase64(j.content:gsub("%s","")));o.close()
exit()
install.lua
```

The published installer embeds its signed manifest and complete package bundle, so a
fresh installation uses only the single API request that downloads `install.lua`.
Explicit `--version` and `--manifest` installs obtain one manifest and one bundled
payload instead of requesting every package separately.

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
node tools/build-release.mjs 3.4.0 PrinceOfCookies/CookieOS cookieos-v3-rewrite RELEASE_KEY
```

The builder creates `dist/release` with the online/offline package tree, hashes,
authenticated manifest, and a single installer containing the matching release key.
Manifest entries contain repository-relative `source` paths plus the repository, Git
ref, and bundled-payload path needed by the GitHub API; they contain no GitHub download
URLs. The generated installer carries that manifest and bundle for rate-limit-friendly
fresh installs.
The rewrite branch workflow automatically runs this builder and commits `release/`
back to the branch. Release-only commits do not trigger another workflow run.

The current release authentication uses a stable public HMAC integrity key embedded
in the generated installer. It detects accidental corruption and inconsistent files,
but cannot provide publisher-only signatures. Treat it as integrity checking until
the release format moves to public-key signatures.
