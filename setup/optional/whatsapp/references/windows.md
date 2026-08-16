# Windows setup

## Prerequisites

Require Git, Go matching the repository `go` directive, and a C compiler because `go-sqlite3` uses CGO. Prefer existing installations. If installation is needed, use an available trusted package manager and explain any UAC prompt before invoking it.

Typical tools:

- Git: `Git.Git`
- Go: `GoLang.Go`
- MSYS2: `MSYS2.MSYS2`, with `mingw-w64-ucrt-x86_64-gcc`
- Service manager: `NSSM.NSSM`
- FFmpeg: optional, required only for conversion to WhatsApp voice-note format

After installing tools, refresh the current process PATH and verify actual versions. Do not assume `winget` exists merely because the OS is Windows.

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;$env:PATH"
$env:CGO_ENABLED = "1"
git --version
go version
gcc --version
```

## Build

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;$env:PATH"
$env:CGO_ENABLED = "1"

Push-Location "$repo\whatsapp-bridge"
go mod download
go build -o whatsapp-bridge.exe .
Pop-Location

Push-Location "$repo\whatsapp-mcp-server"
go mod download
go build -o whatsapp-mcp.exe .
Pop-Location
```

Stop the service only for the shortest period needed to replace an in-use binary. If the build writes directly over a running executable and fails, build to a temporary filename, stop the service, atomically replace the executable, then restart.

## Cryptographic secrets

Use the .NET cryptographic generator, not `Get-Random`:

```powershell
$apiBytes = [byte[]]::new(32)
$jwtBytes = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($apiBytes)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($jwtBytes)
$apiKey = [Convert]::ToHexString($apiBytes).ToLowerInvariant()
$jwtSecret = [Convert]::ToHexString($jwtBytes).ToLowerInvariant()
```

Write `.env` files without echoing values. Restrict their ACLs to the current user and required service identity when practical.

## Background service

Reuse an existing `WhatsAppBridge` NSSM service when its binary path and working directory are correct. Back up its configuration before replacing it. For a new service, configure:

- Application: `<repo>\whatsapp-bridge\whatsapp-bridge.exe`
- Working directory: `<repo>\whatsapp-bridge`
- Startup: automatic
- Restart: on unexpected exit
- Environment: bridge variables from `.env`
- Rotating stdout/stderr logs with bounded size

Avoid deleting and recreating a correct service during every upgrade. Update only fields that changed, restart once, then verify both NSSM and its child `whatsapp-bridge.exe` process.

When elevation is required, create a narrowly scoped temporary PowerShell script, show the user the exact purpose of the UAC request, run it with `Start-Process -Verb RunAs -Wait`, and remove the temporary script afterward. Never embed reusable secrets in a world-readable temporary file.

## Verification

```powershell
Get-Service WhatsAppBridge
Get-CimInstance Win32_Service -Filter "Name='WhatsAppBridge'" |
  Select-Object Name, State, StartMode, PathName, ProcessId
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -eq 'whatsapp-bridge.exe' } |
  Select-Object ProcessId, ParentProcessId, ExecutablePath, CreationDate
```

Confirm the child process path, binary timestamp, port 8080 listener, authenticated health state, and recent logs.
