$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Prefix = if ($env:GROK_ULTRA_PREFIX) { $env:GROK_ULTRA_PREFIX } else { Join-Path $HOME ".local" }
$DistRoot = if ($env:GROK_ULTRA_DIST_DIR) { $env:GROK_ULTRA_DIST_DIR } else { Join-Path $Root "dist" }
$AppDir = Join-Path $Prefix "lib\grok-ultra"
$BinDir = Join-Path $Prefix "bin"

& (Join-Path $PSScriptRoot "build-grok-ultra.ps1")
if ($LASTEXITCODE -ne 0) { throw "build-grok-ultra.ps1 failed" }

$Arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
    "X64" { "x86_64" }
    "Arm64" { "aarch64" }
    default { throw "Unsupported architecture" }
}
$PackageDir = Join-Path $DistRoot "grok-ultra-windows-$Arch"

Remove-Item $AppDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item $AppDir -ItemType Directory -Force | Out-Null
New-Item $BinDir -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $PackageDir "bin") $AppDir -Recurse
Copy-Item (Join-Path $PackageDir "libexec") $AppDir -Recurse
Copy-Item (Join-Path $PackageDir "README.txt") $AppDir

# Keep the real launcher next to its private libexec directory. The PATH entry
# is only a tiny forwarding shim, so moving it cannot break relative paths.
$Shim = @"
@echo off
call "$AppDir\bin\grok-ultra.cmd" %*
exit /b %ERRORLEVEL%
"@
Set-Content -Path (Join-Path $BinDir "grok-ultra.cmd") -Value $Shim -Encoding Ascii

Write-Host "Installed isolated Grok Ultra:"
Write-Host "  command: $(Join-Path $BinDir 'grok-ultra.cmd')"
Write-Host "  program: $AppDir"
Write-Host "  state:   $(if ($env:GROK_ULTRA_HOME) { $env:GROK_ULTRA_HOME } else { Join-Path $HOME '.grok-ultra' })"
Write-Host ""
Write-Host "The official grok command and ~/.grok are untouched."
