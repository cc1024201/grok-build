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
| User Agent definitions and bundled Agent cache | `~/.grok/agents`, `~/.grok/bundled/agents` | `~/.grok-ultra/agents`, `~/.grok-ultra/bundled/agents` |
| Default agent | normal configured agent | `grok-build-ultra` |
| Auto updater | upstream behavior | disabled |
| Explicit `update` command | upstream behavior | refused by launcher |

The launcher deliberately overrides ambient `GROK_HOME`, `GROK_AUTH_PATH`, `GROK_LEADER_SOCKET`, and `GROK_SESSION_PATH` values so an existing official-Grok shell environment cannot accidentally reconnect the isolated build to official state. It also sets the isolated-distribution marker, which disables upstream's legacy fallback that would otherwise continue reading user Agent definitions from the literal official `~/.grok` tree when `GROK_HOME` points elsewhere.

The launcher rejects:

- `GROK_ULTRA_HOME=~/.grok`;
- a `GROK_ULTRA_HOME` equal to the ambient official `GROK_HOME`;
- `GROK_ULTRA_AUTH_PATH=~/.grok/auth.json`;
- a `GROK_ULTRA_AUTH_PATH` equal to the ambient official `GROK_AUTH_PATH`;
- the explicit `update` command.

Product-specific overrides are available:

```bash
GROK_ULTRA_HOME=/absolute/state/root grok-ultra
GROK_ULTRA_AUTH_PATH=/absolute/auth.json grok-ultra
GROK_ULTRA_AGENT=grok-build-ultra grok-ultra
GROK_ULTRA_LEADER_SOCKET=/absolute/leader.sock grok-ultra
GROK_ULTRA_SESSION_PATH=/absolute/session.json grok-ultra
```

The first run uses a separate credential file and therefore may request login even when official Grok is already authenticated. Logging into the same account is safe; the two token files remain independent. Copying or symlinking the official `auth.json` into the isolated tree is intentionally not part of the installation process.

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

No file named `grok` is created, replaced, or removed. `~/.grok` is not used as the global state root or legacy user-Agent source by the packaged launcher.

## Verify the boundary

The repository ships platform-specific launcher tests:

```bash
bash scripts/test-grok-ultra-isolation.sh
```

```powershell
.\scripts\test-grok-ultra-isolation.ps1
```

They verify that ambient official-Grok paths are replaced, the updater is refused, and attempts to reuse the official state or credential paths fail closed. The distribution workflow additionally builds the Linux package, launches its real release binary with `--version`, and asserts that an official-state sentinel and `~/.grok` remain untouched.

After a local installation, these checks should show separate commands and separate global roots:

```bash
command -v grok
command -v grok-ultra
printf 'official=%s\nultra=%s\n' "$HOME/.grok" "$HOME/.grok-ultra"
```

## Uninstall

```bash
bash scripts/uninstall-grok-ultra.sh
```

The program is removed while isolated state is preserved. Delete `~/.grok-ultra` separately only when credentials, sessions, memory, logs, caches, and worktrees should also be removed.

## Project-local compatibility boundary

Repository-owned `.grok/` files remain visible to both builds because they are project configuration committed alongside the code, not installation state. The isolated package does not redirect that namespace. This preserves the project's agents, MCP settings, permissions, hooks, workflows, sandbox settings, and skills.

For a validation run that must not even share repository-local `.grok/` files or source edits with official Grok, use Grok Ultra from a separate Git worktree or clone. Redirecting the project namespace to `.grok-ultra/` inside the client would intentionally make it ignore the repository's existing Grok configuration and is therefore a separate product choice, not an installation fix.

Compatibility reads from user `.claude/` and `.agents/` directories remain enabled because they are cross-tool compatibility inputs rather than official Grok installation state. They are not written by the Grok Ultra installer.

System-managed policy such as `/etc/grok` remains readable. It is not an installation collision surface and may be intentionally enforced by an organization. The isolated package does not write to it.

## Windows

```powershell
.\scripts\build-grok-ultra.ps1
.\scripts\install-grok-ultra.ps1
```

The installed command is `grok-ultra.cmd`; the private core executable is stored as `grok-ultra-core.exe`. The PATH launcher is only a forwarding shim to the private application directory, so moving or replacing it cannot cause the core to resolve relative to the official Grok installation. Neither file is named `grok.exe`.
