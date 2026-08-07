$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Prefix = if ($env:GROK_ULTRA_PREFIX) { $env:GROK_ULTRA_PREFIX } else { Join-Path $HOME ".local" }
$AppDir = Join-Path $Prefix "lib\grok-ultra"
$BinDir = Join-Path $Prefix "bin"

& (Join-Path $PSScriptRoot "build-grok-ultra.ps1")
if ($LASTEXITCODE -ne 0) { throw "build-grok-ultra.ps1 failed" }

$Arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
    "X64" { "x86_64" }
    "Arm64" { "aarch64" }
    default { throw "Unsupported architecture" }
}
$PackageDir = Join-Path $Root "dist\grok-ultra-windows-$Arch"

Remove-Item $AppDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item $AppDir -ItemType Directory -Force | Out-Null
New-Item $BinDir -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $PackageDir "bin") $AppDir -Recurse
Copy-Item (Join-Path $PackageDir "libexec") $AppDir -Recurse
Copy-Item (Join-Path $PackageDir "README.txt") $AppDir
Copy-Item (Join-Path $PackageDir "bin\grok-ultra.cmd") (Join-Path $BinDir "grok-ultra.cmd") -Force

Write-Host "Installed isolated Grok Ultra:"
Write-Host "  command: $(Join-Path $BinDir 'grok-ultra.cmd')"
Write-Host "  program: $AppDir"
Write-Host "  state:   $(if ($env:GROK_ULTRA_HOME) { $env:GROK_ULTRA_HOME } else { Join-Path $HOME '.grok-ultra' })"
Write-Host ""
Write-Host "The official grok command and ~/.grok are untouched."
