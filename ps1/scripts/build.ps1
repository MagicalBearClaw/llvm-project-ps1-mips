<#
.SYNOPSIS
  Build the PS1 tool set (or given Ninja targets) for a checkout.

.EXAMPLE
  ps1\scripts\build.ps1                              # default tool set
  ps1\scripts\build.ps1 check-llvm-codegen-mips      # any Ninja target
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [string[]]$Targets,
    [string]$SourceDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$BuildDir
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ps1-env.ps1')

if (-not $BuildDir) { $BuildDir = Join-Path $SourceDir 'build' }
if (-not (Test-Path (Join-Path $BuildDir 'build.ninja'))) {
    & (Join-Path $PSScriptRoot 'configure.ps1') -SourceDir $SourceDir -BuildDir $BuildDir
}

if (-not $Targets) {
    $Targets = 'clang', 'lld', 'llc', 'llvm-mc', 'llvm-objdump', 'FileCheck',
               'llvm-readobj', 'llvm-objcopy', 'not', 'count', 'llvm-config'
}

$sw = [Diagnostics.Stopwatch]::StartNew()
ninja -C $BuildDir @Targets
$code = $LASTEXITCODE
$sw.Stop()
Write-Host ("ninja {0} finished in {1:hh\:mm\:ss} (exit {2})" -f ($Targets -join ' '), $sw.Elapsed, $code)
if ($code -ne 0) { exit $code }
