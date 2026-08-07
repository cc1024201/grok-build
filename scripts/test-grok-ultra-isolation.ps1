$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$source = Get-Content (Join-Path $PSScriptRoot "build-grok-ultra.ps1") -Raw
$pattern = '(?s)\$Launcher = @''\r?\n(.*?)\r?\n''@'
$match = [regex]::Match($source, $pattern)
if (-not $match.Success) { throw "Unable to extract grok-ultra.cmd launcher template" }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("grok-ultra-launcher-test-" + [Guid]::NewGuid().ToString("N"))
$bin = Join-Path $testRoot "bin"
$libexec = Join-Path $testRoot "libexec"
New-Item $bin -ItemType Directory -Force | Out-Null
New-Item $libexec -ItemType Directory -Force | Out-Null
Set-Content (Join-Path $bin "grok-ultra.cmd") $match.Groups[1].Value -Encoding Ascii
Copy-Item $env:ComSpec (Join-Path $libexec "grok-ultra-core.exe")
$launcher = Join-Path $bin "grok-ultra.cmd"

function Invoke-IsolatedLauncher([string[]]$LauncherArgs) {
    $token = [Guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $testRoot "$token.stdout"
    $stderrPath = Join-Path $testRoot "$token.stderr"
    $commandLine = '"' + $launcher + '" ' + ($LauncherArgs -join ' ')
    $process = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/c', $commandLine) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { "" }
        Stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { "" }
    }
}

try {
    $env:GROK_HOME = "C:\official-grok"
    $env:GROK_AUTH_PATH = "C:\official-grok\auth.json"
    $env:GROK_LEADER_SOCKET = "C:\official-grok\leader.sock"
    $env:GROK_SESSION_PATH = "C:\official-grok\session.json"
    Remove-Item Env:GROK_ULTRA_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:GROK_ULTRA_AUTH_PATH -ErrorAction SilentlyContinue

    $normal = Invoke-IsolatedLauncher @('/c', 'set', 'GROK_')
    if ($normal.ExitCode -ne 0) {
        throw "launcher failed: $($normal.ExitCode)`nstdout:`n$($normal.Stdout)`nstderr:`n$($normal.Stderr)"
    }
    $expectedHome = Join-Path $env:USERPROFILE ".grok-ultra"
    if ($normal.Stdout -notmatch [regex]::Escape("GROK_HOME=$expectedHome")) {
        throw "isolated home missing:`n$($normal.Stdout)"
    }
    if ($normal.Stdout -notmatch [regex]::Escape("GROK_AUTH_PATH=$expectedHome\auth.json")) {
        throw "isolated auth path missing:`n$($normal.Stdout)"
    }
    if ($normal.Stdout -notmatch "GROK_AGENT=grok-build-ultra") { throw $normal.Stdout }
    if ($normal.Stdout -notmatch "GROK_DISABLE_AUTOUPDATER=1") { throw $normal.Stdout }
    if ($normal.Stdout -match 'C:\\official-grok\\leader.sock|C:\\official-grok\\session.json') {
        throw "official leader/session leaked:`n$($normal.Stdout)"
    }

    $update = Invoke-IsolatedLauncher @('update')
    if ($update.ExitCode -ne 2) {
        throw "update command was not refused: $($update.ExitCode)`n$($update.Stderr)"
    }

    $env:GROK_ULTRA_HOME = Join-Path $env:USERPROFILE ".grok"
    $officialHome = Invoke-IsolatedLauncher @('/c', 'exit', '0')
    if ($officialHome.ExitCode -ne 2) {
        throw "official state root was not refused: $($officialHome.ExitCode)`n$($officialHome.Stderr)"
    }

    Write-Host "PASS: Windows grok-ultra launcher isolates command state and rejects official updater/state paths."
} finally {
    Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
