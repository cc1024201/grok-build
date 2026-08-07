# Isolated Grok Ultra self-use package

The self-use build must coexist with the official Grok installation. A different executable filename alone is insufficient: upstream Grok stores configuration, credentials, sessions, leader state, logs, memory, worktrees, plugin caches, and updater state below `GROK_HOME`, which defaults to `~/.grok`.

## Isolation contract

The packaged command is `grok-ultra`, never `grok`. Its launcher enforces:

| Surface | Official Grok | Isolated Grok Ultra |
|---|---|---|
| Command | `grok` | `grok-ultra` |
| Default state root | `~/.grok` | `~/.grok-ultra` |
| Credentials | `~/.grok/auth.json` | `~/.grok-ultra/auth.json` |
| Sessions, leader state, logs, memory, worktrees, plugins | below `~/.grok` | below `~/.grok-ultra` |
| Default agent | normal configured agent | `grok-build-ultra` |
| Auto updater | upstream behavior | disabled |
| Explicit `update` command | upstream behavior | refused by launcher |

The launcher deliberately overrides ambient `GROK_HOME`, `GROK_AUTH_PATH`, `GROK_LEADER_SOCKET`, and `GROK_SESSION_PATH` values so an existing official-Grok shell environment cannot accidentally reconnect the isolated build to official state.

Product-specific overrides are available:

```bash
GROK_ULTRA_HOME=/absolute/state/root grok-ultra
GROK_ULTRA_AUTH_PATH=/absolute/auth.json grok-ultra
GROK_ULTRA_AGENT=grok-build-ultra grok-ultra
GROK_ULTRA_LEADER_SOCKET=/absolute/leader.sock grok-ultra
GROK_ULTRA_SESSION_PATH=/absolute/session.json grok-ultra
```

## Build and package

```bash
bash scripts/build-grok-ultra.sh
```

This builds the upstream composition binary and packages it as:

```text
dist/grok-ultra-<platform>-<arch>/
  bin/grok-ultra
  libexec/grok-ultra-core
  README.txt
```

The archive is written beside the directory with a SHA-256 file.

## Install without touching official Grok

```bash
bash scripts/install-grok-ultra.sh
```

The default installation is:

```text
~/.local/bin/grok-ultra
~/.local/lib/grok-ultra/
~/.grok-ultra/
```

No file named `grok` is created, replaced, or removed. `~/.grok` is not used as the global state root by the packaged launcher.

## Uninstall

```bash
bash scripts/uninstall-grok-ultra.sh
```

The program is removed while isolated state is preserved. Delete `~/.grok-ultra` separately only when credentials, sessions, memory, logs, caches, and worktrees should also be removed.

## Project-local compatibility boundary

Repository-owned `.grok/` files remain visible to both builds because they are project configuration committed alongside the code, not installation state. The isolated package does not redirect that namespace. A future strict-project-isolation mode could introduce `.grok-ultra/`, but doing so would intentionally stop inheriting existing project agents, MCP settings, permissions, and skills and therefore requires a separate compatibility decision.

System-managed policy such as `/etc/grok` remains readable. It is not an installation collision surface and may be intentionally enforced by an organization. The isolated package does not write to it.

## Windows

```powershell
.\scripts\build-grok-ultra.ps1
.\scripts\install-grok-ultra.ps1
```

The installed command is `grok-ultra.cmd`; the core executable is stored as `grok-ultra-core.exe`. Neither file is named `grok.exe`.
