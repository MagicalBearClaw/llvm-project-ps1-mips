<#
.SYNOPSIS
  Remove a ticket worktree and its build directory.

.EXAMPLE
  ps1\scripts\remove-worktree.ps1 MIC-14
  ps1\scripts\remove-worktree.ps1 MIC-14 -Force   # even if not merged
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^MIC-\d+$')]
    [string]$Ticket,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$MainCheckout = 'G:\git\llvm-project-ps1-mips'
$path = Join-Path 'G:\git\llvm-ps1-worktrees' $Ticket

if (-not (Test-Path $path)) { throw "No worktree at $path" }

if (-not $Force) {
    $dirty = git -C $path status --porcelain --untracked-files=normal
    if ($dirty) { throw "Worktree $Ticket has uncommitted changes. Use -Force to discard." }
}

# The build dir is ignored by git; remove it first so worktree removal is quick.
$build = Join-Path $path 'build'
if (Test-Path $build) { Remove-Item -Recurse -Force $build }

$removeArgs = @('worktree', 'remove', $path)
if ($Force) { $removeArgs += '--force' }
git -C $MainCheckout @removeArgs
if ($LASTEXITCODE -ne 0) { throw 'git worktree remove failed.' }
git -C $MainCheckout worktree prune

Write-Host "Removed worktree $Ticket. The branch is kept; delete it after the PR merges."
