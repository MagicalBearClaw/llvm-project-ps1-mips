<#
.SYNOPSIS
  Create a worktree for a Linear ticket, branched from origin/ps1/main.

.EXAMPLE
  ps1\scripts\new-worktree.ps1 MIC-14 r3000a-processor
  # -> G:\git\llvm-ps1-worktrees\MIC-14 on branch MIC-14-r3000a-processor
  #    with its own build directory G:\git\llvm-ps1-worktrees\MIC-14\build

.NOTES
  At most $MaxActive worktrees may exist at once (the main checkout does not
  count). Remove finished ones with remove-worktree.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^MIC-\d+$')]
    [string]$Ticket,

    [Parameter(Mandatory, Position = 1)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$Name,

    [string]$Base = 'origin/ps1/main',
    [switch]$NoConfigure
)

$ErrorActionPreference = 'Stop'

$MaxActive    = 3
$MainCheckout = 'G:\git\llvm-project-ps1-mips'
$WorktreeRoot = 'G:\git\llvm-ps1-worktrees'

$path   = Join-Path $WorktreeRoot $Ticket
$branch = "$Ticket-$Name"

function Get-Ps1Worktrees {
    $main = (Resolve-Path $MainCheckout).Path.TrimEnd('\')
    git -C $MainCheckout worktree list --porcelain |
        Where-Object { $_ -like 'worktree *' } |
        ForEach-Object { ($_ -replace '^worktree ', '') -replace '/', '\' } |
        Where-Object { $_.TrimEnd('\') -ne $main }
}

if (Test-Path $path) { throw "Worktree path already exists: $path" }

$active = @(Get-Ps1Worktrees)
if ($active.Count -ge $MaxActive) {
    throw ("Refusing to create worktree {0}: {1} already active (max {2}):`n  {3}" -f
        $Ticket, $active.Count, $MaxActive, ($active -join "`n  "))
}

git -C $MainCheckout fetch origin ps1/main
if ($LASTEXITCODE -ne 0) { throw 'git fetch failed.' }

New-Item -ItemType Directory -Force $WorktreeRoot | Out-Null
git -C $MainCheckout worktree add -b $branch $path $Base
if ($LASTEXITCODE -ne 0) { throw 'git worktree add failed.' }

Write-Host "Created $path on $branch (from $Base)."

if (-not $NoConfigure) {
    & (Join-Path $path 'ps1\scripts\configure.ps1') -SourceDir $path
}
