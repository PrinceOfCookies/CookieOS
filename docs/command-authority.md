# CookieSecurity Command Authority security model

The Command Authority is the first CookieSecurity computer installed and the root of
facility trust. Auth is enrolled beneath it and manages ordinary identities and
sessions; it cannot grant Command access.

## Non-negotiable invariants

- Command access requires CL6, the configured Minecraft username, its normal password,
  and that same player within the configured physical radius.
- The Command computer requires a speaker and player detector. Its position comes from
  `gps.locate()` or explicit installation coordinates.
- One failed username, password, proximity, or location check immediately enters global
  lockdown.
- Lockdown is durable across reboots and distributed as signed Command state. Terminals
  also query Command before login so a missed broadcast cannot bypass it.
- Lockdown recovery is local-only. It requires the nearby CL6 player and a distinct
  override password selected during Command installation.
- Normal and override credentials are salted password verifiers, never plaintext, and
  must not be equal.
- Command enrollment precedes Auth enrollment; all later nodes require the Command
  trust identity in addition to their Auth relationship.
- Remote filesystem and remote shell access are forbidden. The unrestricted shell is
  local to the physically authenticated Command computer.
- Every login, failure, lockdown, override attempt, enrollment, and trust change is
  appended to the audit log.

## Installation order

1. Install and commission the Command Authority.
2. Enroll one Auth manager with a Command-generated one-use code.
3. Create normal users through Auth.
4. Enroll Auth terminals and service nodes through Command.
5. Pair their user-session path with Auth.

The legacy unrestricted `command-terminal` implementation is transitional and must
not be treated as the completed Command Authority.
