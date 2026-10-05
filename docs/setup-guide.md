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

## 2. Install the Command Authority first

Choose **Command Authority** on a computer with a speaker, player detector, and modem.
The installer requires the CL6 Minecraft username, a normal password, a different
emergency override password, and a GPS or explicitly entered physical position.

After boot, the configured player must be within the chosen radius and enter the CL6
password before the unrestricted local shell opens. Run `command-enroll` in that shell
to generate a one-use enrollment code for the Auth server or any later node.

One failed username, password, location, or proximity factor immediately locks all
CookieSecurity authentication. Recovery is possible only at this computer with the
nearby configured player and the separate override password.

## 3. Install the CookieSecurity Auth manager

Choose **Auth/core server** (or **Hybrid core + relay**), give it a recognizable node
name such as `cookiesecurity-authority`, select the modem side, and create the initial
administrator. The authority preset includes a local terminal specifically for
bootstrapping other nodes.

During setup, enter the Command Authority node name. Run `command-enroll` at Command
when the Auth installer asks to enroll. After reboot, use the Auth computer itself:

```text
login admin
```

Replace `admin` with the administrator name chosen during installation. Auth manages
ordinary CL0-CL5 users and sessions. It cannot grant CL6 Command access.

## 4. Install and enroll a terminal

Run the same installer on another computer and choose **Auth terminal**. Use a clear
node name such as `security-desk-01`. When asked to enroll, run `command-enroll` from
the physically authenticated Command shell, then enter that code on the terminal.

After enrollment succeeds, reboot the terminal and log in:

```text
login admin
```

Command enrollment establishes node trust. Login establishes an Auth user session.
Both are required: enrolling a computer does not automatically log a person in.

### Command access

There is one Command Authority. Its unrestricted CraftOS shell includes `ls`, `edit`,
`delete`, `copy`, and normal program execution, but opens only after CL6 password and
physical-player verification. It does not provide remote filesystem control.

## 5. Create non-administrator logins

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

## 6. Terminal help and monitors

Use `help` for the command list. If the computer has an attached monitor, use:

```text
help monitor
```

CookieOS finds the first attached monitor and leaves the complete command list on it.

## 7. Add other node types

- **Relay** forwards packets between attached modem segments and does not host Auth.
- **Player tracker** requires a `player_detector` peripheral.
- **Hybrid core + relay** combines the authority, local terminal, and relay roles.
- **Custom node** lets an advanced operator choose services and node mode manually.
- **Speaker zone** hosts authenticated sound and alarm controls on attached speakers.
- **Chat gateway** sends authenticated messages through an attached chat box and can
  optionally expose configured `!help`, `!where`, and `!security` chat commands.

Give every computer a unique node name. The suggested `cookieos-NUMBER` uses the
ComputerCraft computer ID only as a convenient default and can be replaced.

Enroll every non-Command node using a fresh Command-generated code. Codes expire
and cannot be reused.

From the Command Authority, run `cookiesecurity` for local configuration, enrollment,
recovery, logs, and shell shortcuts. Speaker controls from an Auth terminal are
`sound [Minecraft sound]`, `alarm [count]`, and `audiostop`; use `chat <message>` for
the chat gateway.

## 8. Updates, repairs, and reconfiguration

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

## 9. Original CookieOS versus the v3 rewrite

The original CookieOS remains on the repository's `main` branch. The distributed v3
work lives on `cookieos-v3-rewrite`; it has not overwritten `main`.

The v3 release is a new runtime and boot path. The obsolete `os/` programs and the
legacy `cosUtils`-based replacements are removed during upgrade. A small maintained
`programReplacements/` toolkit is installed for the authenticated Command shell
(`cs`, `nodeinfo`, `logs`, `update`, `recover`, `enroll`, and `revoke`). If v3 replaces
an existing `/startup.lua`, the installer saves it as `/startup.lua.cookieos.bak`;
uninstall restores that backup. Obsolete files are backed up before removal and are
restored by rollback if an update fails.

Do not assume the classic interface and v3 runtime are a finished dual-boot system.
Preserve an original installation or use the `main` branch until the classic UI is
explicitly adapted as a v3 front end.

## 10. Recommended commissioning check

1. Boot Command and complete CL6 physical authentication.
2. Run `command-enroll` and enroll Auth.
3. Reboot the terminal and log in.
4. Run `nodes`, `services`, and `security`.
5. Create a low-clearance test account and verify its access.
6. Test `help monitor` if a monitor is attached.
7. Keep the installer and recovery path available before deploying more nodes.
