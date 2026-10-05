# Copies the launcher into project folders, or checks that their copies are identical.
#   .\sync.ps1 <project-dir>...          copy run.sh and run.ps1, record this commit in run.version
#   .\sync.ps1 -Check <project-dir>...   exit 1 if a vendored copy differs from this repository
param([switch]$Check, [Parameter(ValueFromRemainingArguments = $true)][string[]]$ProjectDirs)
$ErrorActionPreference = 'Stop'
$Files = 'run.sh', 'run.ps1'

function Stop-Sync([string]$Message) {
    [Console]::Error.WriteLine("sync.ps1: $Message")
    exit 2
}

if (-not $ProjectDirs) { Stop-Sync 'usage: sync.ps1 [-Check] <project-dir>...' }
foreach ($dir in $ProjectDirs) { if (-not (Test-Path -PathType Container $dir)) { Stop-Sync "not a folder: $dir" } }

if (-not $Check) {
    # run.version must name a commit that really contains the copied files.
    git -C $PSScriptRoot diff --quiet HEAD -- @Files
    if ($LASTEXITCODE -ne 0) { Stop-Sync 'commit the changes to run.sh and run.ps1 before syncing' }
    $commit = git -C $PSScriptRoot rev-parse HEAD
}

$drift = 0
foreach ($dir in $ProjectDirs) {
    $target = (Resolve-Path $dir).Path
    if (-not $Check) {
        foreach ($f in $Files) { Copy-Item -Force (Join-Path $PSScriptRoot $f) (Join-Path $target $f) }
        [IO.File]::WriteAllText((Join-Path $target 'run.version'), "$commit`n", (New-Object Text.UTF8Encoding $false))
        Write-Host "synced $dir at $commit"
        continue
    }
    $versionFile = Join-Path $target 'run.version'
    $version = if (Test-Path $versionFile) { [IO.File]::ReadAllText($versionFile).Trim() } else { 'no run.version' }
    foreach ($f in $Files) {
        $source = Join-Path $PSScriptRoot $f
        $copy = Join-Path $target $f
        if ((Test-Path $copy) -and (Get-FileHash $copy).Hash -eq (Get-FileHash $source).Hash) {
            Write-Host "ok    $dir/$f"
        } else {
            Write-Host "DRIFT $dir/$f differs from $source (vendored from: $version)"
            $drift = 1
        }
    }
}
exit $drift
