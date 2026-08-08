$ErrorActionPreference = "Stop"
$Prefix = if ($env:GROK_ULTRA_PREFIX) { $env:GROK_ULTRA_PREFIX } else { Join-Path $HOME ".local" }
$AppDir = Join-Path $Prefix "lib\grok-ultra"
$Launcher = Join-Path $Prefix "bin\grok-ultra.cmd"
Remove-Item $Launcher -Force -ErrorAction SilentlyContinue
Remove-Item $AppDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Removed the grok-ultra program."
Write-Host "Isolated state was preserved at: $(if ($env:GROK_ULTRA_HOME) { $env:GROK_ULTRA_HOME } else { Join-Path $HOME '.grok-ultra' })"
