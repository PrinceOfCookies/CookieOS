# CookieOS complete setup guide

This guide sets up a CookieSecurity authority, terminal clients, relays, trackers,
logins, pairing, updates, and recovery. Complete the authority first.

## 1. Get the installer

Open the `cookieos-v3-rewrite` branch on GitHub and download
`release/install.lua`, or copy that file from a downloaded repository archive. Drag
the file onto the CC:Tweaked computer and run:

```text
install.lua
```

The release file embeds every required package. A normal fresh install does not make
additional GitHub API requests.

## 2. Install the CookieSecurity authority

Choose **Auth/core server** (or **Hybrid core + relay**), give it a recognizable node
name such as `cookiesecurity-authority`, select the modem side, and create the initial
administrator. The authority preset includes a local terminal specifically for
bootstrapping other nodes.

After reboot, use the authority computer itself:

```text
login admin
paircode
```

Replace `admin` with the administrator name chosen during installation. The authority
prints a 16-character, one-use code valid for about two minutes. The new node never
creates its own pairing code.

## 3. Install and pair a terminal

Run the same installer on another computer and choose **Terminal client**. Use a clear
node name such as `security-desk-01`. When asked to pair, first run `paircode` on the
logged-in authority console, then enter that code on the terminal.

After pairing succeeds, reboot the terminal and log in:

```text
login admin
```

Pairing establishes node trust. Login establishes a user session. Both are required:
pairing a computer does not automatically log a person in.

## 4. Create non-administrator logins

From a logged-in administrator terminal:

```text
useradd operator 2 Control Room Operator
useradd supervisor 4 Security Supervisor
```

The command prompts twice for the new password. Clearance is `0` through `5`; higher
levels grant more built-in permissions. Remove an account with:

```text
userdel operator
```

List accounts with `users`, inspect one with `whois <user>`, and change a password
with `passwd <user>`.

## 5. Terminal help and monitors

Use `help` for the command list. If the computer has an attached monitor, use:

```text
help monitor
```

CookieOS finds the first attached monitor and leaves the complete command list on it.

## 6. Add other node types

- **Relay** forwards packets between attached modem segments and does not host Auth.
- **Player tracker** requires a `player_detector` peripheral.
- **Hybrid core + relay** combines the authority, local terminal, and relay roles.
- **Custom node** lets an advanced operator choose services and node mode manually.

Give every computer a unique node name. The suggested `cookieos-NUMBER` uses the
ComputerCraft computer ID only as a convenient default and can be replaced.

Pair every non-authority node using a fresh authority-generated code. Codes expire
and cannot be reused.

## 7. Updates, repairs, and reconfiguration

Keep a current `release/install.lua` available locally. Run it with:

```text
install.lua --upgrade
install.lua --repair
install.lua --reconfigure
install.lua --recovery
install.lua --uninstall
```

Upgrade and repair preserve node configuration. Reconfigure reruns the role wizard.
Recovery can roll back an update or disable a failing service. Uninstall asks
separately before deleting configuration or CookieOS data.

## 8. Original CookieOS versus the v3 rewrite

The original CookieOS remains on the repository's `main` branch. The distributed v3
work lives on `cookieos-v3-rewrite`; it has not overwritten `main`.

The v3 release is currently a new runtime and boot path, not a completed port of the
original graphical shell. The old `os/`, `startup/`, `programReplacements/`, and
`apis/` trees remain in source control but are intentionally not copied by the v3
release installer. If v3 replaces an existing `/startup.lua`, the installer saves it
as `/startup.lua.cookieos.bak`; uninstall restores that backup.

Do not assume the classic interface and v3 runtime are a finished dual-boot system.
Preserve an original installation or use the `main` branch until the classic UI is
explicitly adapted as a v3 front end.

## 9. Recommended commissioning check

1. Boot the authority and log in locally.
2. Generate a pairing code and pair one terminal.
3. Reboot the terminal and log in.
4. Run `nodes`, `services`, and `security`.
5. Create a low-clearance test account and verify its access.
6. Test `help monitor` if a monitor is attached.
7. Keep the installer and recovery path available before deploying more nodes.
