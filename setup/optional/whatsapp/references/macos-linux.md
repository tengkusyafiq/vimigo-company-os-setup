# macOS and Linux setup

## Prerequisites

Require Git, Go matching the repository `go` directive, and a working C toolchain for CGO. Prefer platform-native trusted packages and verify versions after installation.

macOS:

- Prefer Xcode Command Line Tools for `clang` and Git.
- Use Homebrew for Go or optional FFmpeg when already available.
- Do not claim Homebrew GCC works without Command Line Tools; Homebrew itself generally depends on the tools required for installation and builds.

Linux:

- Install Git and a build toolchain with the detected distribution package manager.
- If the distribution Go version is older than the repository directive, install the official Go archive for the detected architecture.
- Before replacing `/usr/local/go`, resolve and verify the absolute target and preserve a rollback path.

## Build

```bash
cd "$repo/whatsapp-bridge"
CGO_ENABLED=1 go mod download
CGO_ENABLED=1 go build -o whatsapp-bridge .

cd "$repo/whatsapp-mcp-server"
go mod download
go build -o whatsapp-mcp .
```

Generate secrets with `openssl rand -hex 32` or an equivalent OS cryptographic generator. Do not print them in commentary.

## macOS launchd

Use a user LaunchAgent at `~/Library/LaunchAgents/com.user.whatsapp-bridge.plist` unless system-wide operation is explicitly required. Set the absolute executable, working directory, required environment, `RunAtLoad`, and `KeepAlive`. Write logs to a user-owned bounded location rather than an unbounded shared `/tmp` file.

Prefer modern commands where available:

```bash
launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl enable "gui/$(id -u)/com.user.whatsapp-bridge"
launchctl kickstart -k "gui/$(id -u)/com.user.whatsapp-bridge"
```

Validate the plist with `plutil -lint` before loading it.

## Linux systemd user service

Use `~/.config/systemd/user/whatsapp-bridge.service` with absolute paths, `Restart=on-failure`, and `RestartSec=5`. Prefer an `EnvironmentFile=` pointing to a protected file over duplicating secrets directly in the unit.

```ini
[Unit]
Description=WhatsApp MCP bridge
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/absolute/repo/whatsapp-bridge
ExecStart=/absolute/repo/whatsapp-bridge/whatsapp-bridge
EnvironmentFile=/absolute/repo/whatsapp-bridge/.env
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

Then run `systemctl --user daemon-reload`, `enable --now`, and verify with `systemctl --user status` and `journalctl --user -u whatsapp-bridge`. Enabling linger changes account behavior and may require administrator approval; do it only when start-before-login is actually required.
