<#
.SYNOPSIS
  Create (or remove) a sibling git worktree for one addin-batch lane (one US or one standalone bug).

.DESCRIPTION
  Create:
    - Worktree at <Root>\<repoName>-wt-<Id> (sibling of the repo, so relative HintPaths like ..\..\Lib still resolve).
    - Branch <Branch> (required; from addin-batch lanes.branchUser) from <Base> (or reuse the branch if it already exists).
    - packages\ as a directory junction to the main repo's packages\ (no 450 MB copy). Use -CopyPackages to copy instead.
    - Copies harness context: .harness\config.json, addin-story.json, project-map.md, tickets\, features\<each id>.
    - Writes .harness\lane.json (lane id, ticket ids, base, branch, base commit, main repo path).
    - Runs 'msbuild <sln> /t:Restore' for every root .sln (SDK-style projects need obj\project.assets.json). -NoRestore skips.
    - Verifies one RevitAPI/AutoCAD HintPath resolves from the worktree.
  Remove (-Remove):
    - Copies .harness\features\<ids> and .harness\lanes evidence back to the main repo (unless -NoCopyBack).
    - Removes the packages junction safely (rmdir, never recursive delete), then 'git worktree remove'.
    - Never deletes the branch.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File new-worktree.ps1 -Id 40236 -Ids 40236,42033,42066 -Base longpl_20261004 -Branch longpl_20261004_lane40236
  powershell -ExecutionPolicy Bypass -File new-worktree.ps1 -Id 40236 -Remove
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Id,
  [string[]]$Ids,
  [string]$Base = 'DEV',
  [string]$Branch,
  [string]$Repo,
  [string]$Root,
  [switch]$CopyPackages,
  [switch]$Remove,
  [switch]$NoCopyBack,
  [switch]$NoRestore,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Fail([string]$msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Info([string]$msg) { Write-Host $msg }

if (-not $Repo) { $Repo = (& git rev-parse --show-toplevel 2>$null) }
if (-not $Repo) { Fail 'Not inside a git repository; pass -Repo.' }
$Repo = (Resolve-Path $Repo).Path

# Refuse to run from inside a worktree: the main checkout owns the queue.
# In a linked worktree '.git' is a file; in the main checkout it is a directory.
if (-not (Test-Path (Join-Path $Repo '.git') -PathType Container)) {
  Fail "Run this from the main checkout, not from a worktree ($Repo)."
}

$repoName = Split-Path $Repo -Leaf
if (-not $Root) { $Root = Split-Path $Repo -Parent }
$wt = Join-Path $Root "$repoName-wt-$Id"
if (-not $Ids -or $Ids.Count -eq 0) { $Ids = @($Id) }

# ---------------------------------------------------------------- remove
if ($Remove) {
  if (-not (Test-Path $wt)) { Fail "Worktree not found: $wt" }

  if (-not $NoCopyBack) {
    $laneFile = Join-Path $wt '.harness\lane.json'
    if (Test-Path $laneFile) {
      $lane = Get-Content $laneFile -Raw | ConvertFrom-Json
      $Ids = @($lane.ids)
    }
    foreach ($i in $Ids) {
      $src = Join-Path $wt ".harness\features\$i"
      if (Test-Path $src) {
        $dst = Join-Path $Repo ".harness\features\$i"
        New-Item -ItemType Directory -Force $dst | Out-Null
        Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
        Info "Copied back features\$i"
      }
    }
    $laneDst = Join-Path $Repo ".harness\lanes\$Id"
    New-Item -ItemType Directory -Force $laneDst | Out-Null
    if (Test-Path $laneFile) { Copy-Item $laneFile $laneDst -Force }
  }

  $pkg = Join-Path $wt 'packages'
  if (Test-Path $pkg) {
    $item = Get-Item $pkg -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      # rmdir on a junction removes only the link, never the target's contents.
      cmd /c rmdir "`"$pkg`"" | Out-Null
      Info 'Removed packages junction.'
    }
  }

  $status = (& git -C $wt status --porcelain)
  if ($status -and -not $Force) {
    Fail "Worktree has uncommitted changes. Commit/stash them or pass -Force.`n$status"
  }
  if ($Force) { & git -C $Repo worktree remove --force $wt } else { & git -C $Repo worktree remove $wt }
  if ($LASTEXITCODE -ne 0) { Fail 'git worktree remove failed.' }
  & git -C $Repo worktree prune
  Info "Removed worktree $wt (branch kept)."
  exit 0
}

# ---------------------------------------------------------------- create
if (Test-Path $wt) { Fail "Path already exists: $wt" }
# Branch names come from addin-batch (lanes.branchUser, derived from git user.name by scripts/branch-user.mjs);
# never build them from the raw user.name here (spaces / Vietnamese diacritics are not valid in refs).
if (-not $Branch) { Fail 'Pass -Branch (addin-batch computes it from lanes.branchUser, e.g. longpl_20261004_lane1234).' }
& git check-ref-format --branch $Branch | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Invalid branch name: $Branch" }

& git -C $Repo rev-parse --verify --quiet "$Base^{commit}" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Base '$Base' does not exist." }
$baseCommit = (& git -C $Repo rev-parse --short "$Base").Trim()

& git -C $Repo show-ref --verify --quiet "refs/heads/$Branch"
if ($LASTEXITCODE -eq 0) {
  Info "Reusing existing branch $Branch"
  & git -C $Repo worktree add $wt $Branch
} else {
  & git -C $Repo worktree add -b $Branch $wt $Base
}
if ($LASTEXITCODE -ne 0) { Fail 'git worktree add failed.' }

# packages\ (untracked NuGet folder)
$mainPkg = Join-Path $Repo 'packages'
$wtPkg = Join-Path $wt 'packages'
if ((Test-Path $mainPkg) -and -not (Test-Path $wtPkg)) {
  if ($CopyPackages) {
    Copy-Item $mainPkg $wtPkg -Recurse
    Info 'Copied packages\.'
  } else {
    New-Item -ItemType Junction -Path $wtPkg -Target $mainPkg | Out-Null
    Info "packages\ -> junction to $mainPkg"
  }
}

# Harness context (.harness is excluded via the shared .git/info/exclude)
$mainH = Join-Path $Repo '.harness'
$wtH = Join-Path $wt '.harness'
New-Item -ItemType Directory -Force $wtH | Out-Null
foreach ($f in @('config.json', 'addin-story.json', 'addin-batch.json', 'project-map.md')) {
  $p = Join-Path $mainH $f
  if (Test-Path $p) { Copy-Item $p $wtH -Force }
}
$tk = Join-Path $mainH 'tickets'
if (Test-Path $tk) { Copy-Item $tk $wtH -Recurse -Force }
foreach ($i in $Ids) {
  $p = Join-Path $mainH "features\$i"
  if (Test-Path $p) {
    New-Item -ItemType Directory -Force (Join-Path $wtH 'features') | Out-Null
    Copy-Item $p (Join-Path $wtH 'features') -Recurse -Force
  }
}

# Restore PackageReference (SDK-style) projects: obj\project.assets.json is untracked and needed to build.
# packages.config projects use the packages\ junction and need no restore.
if (-not $NoRestore) {
  $msbuild = $null
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (Test-Path $vswhere) {
    $msbuild = & $vswhere -latest -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
  }
  if (-not $msbuild) { $cmd = Get-Command msbuild -ErrorAction SilentlyContinue; if ($cmd) { $msbuild = $cmd.Source } }
  if ($msbuild) {
    foreach ($sln in (Get-ChildItem $wt -Filter *.sln -File)) {
      & $msbuild $sln.FullName /t:Restore /v:q /nologo | Out-Null
      if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: restore failed for $($sln.Name)" -ForegroundColor Yellow }
      else { Info "Restored $($sln.Name)" }
    }
  } else {
    Write-Host 'WARNING: MSBuild not found; run "msbuild <sln> /t:Restore" in the worktree before building.' -ForegroundColor Yellow
  }
}

$lane = [ordered]@{
  id         = $Id
  ids        = $Ids
  base       = $Base
  baseCommit = $baseCommit
  branch     = $Branch
  mainRepo   = $Repo
  worktree   = $wt
  createdAt  = (Get-Date).ToString('s')
}
$lane | ConvertTo-Json | Out-File (Join-Path $wtH 'lane.json') -Encoding utf8

# Verify host API references resolve from the worktree
$hintOk = $null
$csprojs = & git -C $wt ls-files '*.csproj'
foreach ($c in $csprojs) {
  $full = Join-Path $wt $c
  $m = Select-String -Path $full -Pattern '<HintPath>([^<]*(RevitAPI|AcMgd|AcDbMgd|accoremgd)[^<]*)</HintPath>' | Select-Object -First 1
  if ($m) {
    $rel = $m.Matches[0].Groups[1].Value
    $abs = [IO.Path]::GetFullPath((Join-Path (Split-Path $full -Parent) $rel))
    $hintOk = Test-Path $abs
    Info "HintPath check ($c): $abs -> $(if ($hintOk) { 'OK' } else { 'MISSING' })"
    break
  }
}
if ($hintOk -eq $false) {
  Write-Host 'WARNING: host API DLL not found from the worktree. Build will fail; use a -Root next to the repo.' -ForegroundColor Yellow
}

Info ''
Info "Lane $Id ready"
Info "  worktree : $wt"
Info "  branch   : $Branch (from $Base @ $baseCommit)"
Info "  tickets  : $($Ids -join ', ')"
Info "Next: open a Claude Code session in the worktree and run /addin-story <ticket .md>"
