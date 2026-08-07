$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TargetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $Root "target" }
$DistRoot = if ($env:GROK_ULTRA_DIST_DIR) { $env:GROK_ULTRA_DIST_DIR } else { Join-Path $Root "dist" }
$Arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
    "X64" { "x86_64" }
    "Arm64" { "aarch64" }
    default { throw "Unsupported architecture: $($_)" }
}
$PackageName = "grok-ultra-windows-$Arch"
$PackageDir = Join-Path $DistRoot $PackageName
$Archive = Join-Path $DistRoot "$PackageName.zip"

& cargo build --manifest-path (Join-Path $Root "Cargo.toml") -p xai-grok-pager-bin --release
if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }

$Core = Join-Path $TargetDir "release\xai-grok-pager.exe"
if (-not (Test-Path $Core -PathType Leaf)) { throw "Release binary not found: $Core" }

Remove-Item $PackageDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $Archive -Force -ErrorAction SilentlyContinue
New-Item (Join-Path $PackageDir "bin") -ItemType Directory -Force | Out-Null
New-Item (Join-Path $PackageDir "libexec") -ItemType Directory -Force | Out-Null
Copy-Item $Core (Join-Path $PackageDir "libexec\grok-ultra-core.exe")

$Launcher = @'
@echo off
setlocal

if /I "%~1"=="update" (
  echo grok-ultra: self-update is disabled for the isolated self-use build. 1>&2
  echo Rebuild or replace the grok-ultra package instead; the official grok installation is never modified. 1>&2
  exit /b 2
)

if defined GROK_ULTRA_HOME (
  set "ULTRA_HOME=%GROK_ULTRA_HOME%"
) else if defined USERPROFILE (
  set "ULTRA_HOME=%USERPROFILE%\.grok-ultra"
) else (
  echo grok-ultra: USERPROFILE is unset; set GROK_ULTRA_HOME to an absolute writable directory. 1>&2
  exit /b 2
)

set "GROK_HOME=%ULTRA_HOME%"
if defined GROK_ULTRA_AUTH_PATH (
  set "GROK_AUTH_PATH=%GROK_ULTRA_AUTH_PATH%"
) else (
  set "GROK_AUTH_PATH=%ULTRA_HOME%\auth.json"
)
if defined GROK_ULTRA_AGENT (
  set "GROK_AGENT=%GROK_ULTRA_AGENT%"
) else (
  set "GROK_AGENT=grok-build-ultra"
)
set "GROK_DISABLE_AUTOUPDATER=1"
set "GROK_ULTRA_DISTRIBUTION=1"
set "GROK_AUTO_UPDATE="

if defined GROK_ULTRA_LEADER_SOCKET (
  set "GROK_LEADER_SOCKET=%GROK_ULTRA_LEADER_SOCKET%"
) else (
  set "GROK_LEADER_SOCKET="
)
if defined GROK_ULTRA_SESSION_PATH (
  set "GROK_SESSION_PATH=%GROK_ULTRA_SESSION_PATH%"
) else (
  set "GROK_SESSION_PATH="
)

"%~dp0..\libexec\grok-ultra-core.exe" %*
exit /b %ERRORLEVEL%
'@
Set-Content -Path (Join-Path $PackageDir "bin\grok-ultra.cmd") -Value $Launcher -Encoding Ascii

$Readme = @"
Grok Ultra isolated self-use build

Run:
  .\bin\grok-ultra.cmd

Default state root:
  %USERPROFILE%\.grok-ultra

The launcher does not install or replace the official 'grok' command and
refuses the 'update' subcommand. Override the isolated state root with:
  `$env:GROK_ULTRA_HOME='C:\path\to\state'; .\bin\grok-ultra.cmd
"@
Set-Content -Path (Join-Path $PackageDir "README.txt") -Value $Readme -Encoding UTF8

Compress-Archive -Path $PackageDir -DestinationPath $Archive -Force
$Hash = (Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path "$Archive.sha256" -Value "$Hash  $([IO.Path]::GetFileName($Archive))" -Encoding Ascii
Write-Host "Package: $PackageDir"
Write-Host "Archive: $Archive"
