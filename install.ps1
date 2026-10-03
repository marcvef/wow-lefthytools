# Installs LefthyTools into the WoW: Forever AddOns folder.
#   .\install.ps1                 copy the addon (normal install)
#   .\install.ps1 -Link           junction the AddOns entry to this repo, so edits only need /reload
#   .\install.ps1 -GameDir <dir>  use this WoW: Forever folder (the one containing Interface\)
# Without -GameDir the Forever folder (World of Warcraft\_classic_beta_) is found automatically.
param(
	[string]$GameDir,
	[switch]$Link
)

$ErrorActionPreference = "Stop"
$name = "LefthyTools"
$flavor = "_classic_beta_" # WoW: Forever's folder inside the World of Warcraft install
# Addons that are now part of LefthyTools; left installed they'd run twice.
$legacy = @("Mirage")

function Find-ForeverFolder {
	$candidates = New-Object System.Collections.Generic.List[string]
	# 1. Battle.net's own list of installs (product.db holds the paths as plain text).
	$db = Join-Path $env:ProgramData "Battle.net\Agent\product.db"
	if (Test-Path $db) {
		$text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($db))
		foreach ($m in [regex]::Matches($text, '[A-Za-z]:[\\/][^\x00-\x1f"<>|*?]*?World of Warcraft')) {
			$candidates.Add($m.Value)
		}
	}
	# 2. The usual places on every local drive.
	$parents = "", "Games", "Program Files (x86)", "Program Files", "Blizzard", "Games\Blizzard", "Battle.net"
	foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
		foreach ($parent in $parents) {
			$candidates.Add((Join-Path (Join-Path $drive.Root $parent) "World of Warcraft"))
		}
	}
	foreach ($wow in $candidates) {
		$dir = Join-Path $wow $flavor
		if (Test-Path (Join-Path $dir "Interface")) { return $dir }
	}
	return $null
}

if (-not $GameDir) {
	$GameDir = Find-ForeverFolder
	if (-not $GameDir) {
		throw "WoW: Forever folder not found. Run again with -GameDir `"<...>\World of Warcraft\$flavor`"."
	}
}

$src = Join-Path $PSScriptRoot $name
$addons = Join-Path $GameDir "Interface\AddOns"
if (-not (Test-Path $addons)) { New-Item -ItemType Directory -Path $addons | Out-Null }

function Remove-AddonFolder([string]$path) {
	if (-not (Test-Path $path)) { return }
	$item = Get-Item $path -Force
	if ($item.LinkType) {
		# rmdir removes only the junction, never the files it points to.
		cmd /c rmdir "$path" | Out-Null
	} else {
		Remove-Item $path -Recurse -Force
	}
}

foreach ($old in $legacy) {
	$oldPath = Join-Path $addons $old
	if (Test-Path $oldPath) {
		Remove-AddonFolder $oldPath
		Write-Output "Removed old standalone addon: $oldPath"
	}
}

$dst = Join-Path $addons $name
Remove-AddonFolder $dst

if ($Link) {
	New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
	Write-Output "Linked $dst -> $src"
} else {
	Copy-Item $src $dst -Recurse
	Write-Output "Copied to $dst"
}
