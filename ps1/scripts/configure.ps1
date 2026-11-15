<#
.SYNOPSIS
  Configure a PS1 development build of a checkout (main or worktree).

.EXAMPLE
  ps1\scripts\configure.ps1                 # this checkout, build dir .\build
  ps1\scripts\configure.ps1 -Fresh          # wipe the CMake cache first
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    # Checkout root. Defaults to the checkout containing this script.
    [string]$SourceDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    # Build directory. Defaults to <SourceDir>\build.
    [string]$BuildDir,
    [switch]$Fresh
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ps1-env.ps1')

if (-not $BuildDir) { $BuildDir = Join-Path $SourceDir 'build' }

$cmakeArgs = @(
    '-G', 'Ninja',
    '-S', (Join-Path $SourceDir 'llvm'),
    '-B', $BuildDir,
    '-C', (Join-Path $SourceDir 'ps1\cmake\ps1-dev.cmake')
)
if ($Fresh) { $cmakeArgs += '--fresh' }

cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed ($LASTEXITCODE)." }
