<#
.SYNOPSIS
  Prepare the current PowerShell session for building the PS1 LLVM fork.

.DESCRIPTION
  Dot-source this script: `. ps1\scripts\ps1-env.ps1`.
  - Enters the Visual Studio x64 developer environment (headers, libs).
  - Puts Ninja and sccache (winget links) on PATH.
  - Points sccache at G:\git\ps1-tools\sccache.
  - Sets SCCACHE_BASEDIRS to every checkout of the fork, so worktrees share
    cache entries, and restarts the sccache server when that list changes.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$Ps1Root      = 'G:\git'
$MainCheckout = Join-Path $Ps1Root 'llvm-project-ps1-mips'
$ToolsDir     = Join-Path $Ps1Root 'ps1-tools'

# --- Visual Studio developer environment --------------------------------------
if (-not $env:VSINSTALLDIR) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vs = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $vs) { throw 'No Visual Studio with the C++ x64 tools found.' }
    # vcvars batch files call vswhere by name.
    $env:PATH = "$(Split-Path $vswhere);$env:PATH"
    Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation `
        -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
}

# --- Tools on PATH -------------------------------------------------------------
$wingetLinks = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
$llvmHost    = 'C:\Program Files\LLVM\bin'
foreach ($dir in @($wingetLinks, $llvmHost)) {
    if ((Test-Path $dir) -and -not (($env:PATH -split ';') -contains $dir)) {
        $env:PATH = "$dir;$env:PATH"
    }
}
foreach ($tool in 'ninja', 'sccache', 'clang-cl', 'lld-link', 'cmake', 'python') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' not found on PATH."
    }
}

# --- sccache -------------------------------------------------------------------
$env:SCCACHE_DIR        = Join-Path $ToolsDir 'sccache'
$env:SCCACHE_CACHE_SIZE = '60G'
New-Item -ItemType Directory -Force $env:SCCACHE_DIR | Out-Null

# Every checkout of the fork (main + worktrees) is a base dir, so the same
# source file hashes the same no matter which checkout compiles it.
$checkouts = git -C $MainCheckout worktree list --porcelain |
    Where-Object { $_ -like 'worktree *' } |
    ForEach-Object { ($_ -replace '^worktree ', '') -replace '/', '\' }
$baseDirs = ($checkouts | Sort-Object -Unique) -join ';'

if ($env:SCCACHE_BASEDIRS -ne $baseDirs -or -not $global:Ps1SccacheStarted) {
    $env:SCCACHE_BASEDIRS = $baseDirs
    # The server reads its config at start-up; restart it to pick up changes.
    sccache --stop-server *> $null
    sccache --start-server | Out-Null
    $global:Ps1SccacheStarted = $true
}

Write-Host "PS1 build env ready. sccache dir: $env:SCCACHE_DIR"
Write-Host "  base dirs: $env:SCCACHE_BASEDIRS"
