<# : LefthyTools installer for WoW: Forever - double-click to install or update
@echo off
rem One standalone file: everything after this batch part is install.ps1 (PowerShell). It downloads
rem the latest LefthyTools from https://github.com/marcvef/wow-lefthytools and installs it into
rem WoW: Forever's Interface\AddOns folder. Settings (WTF folder) are kept.
setlocal
title LefthyTools
set "LEFTHYTOOLS_INSTALLER=%~f0"
set "LEFTHYTOOLS_INSTALLER_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText($env:LEFTHYTOOLS_INSTALLER))) %*"
echo.
pause
exit /b
#>
# LefthyTools installer and updater for WoW: Forever (Windows).
#
# Players: double-click Update-LefthyTools.cmd, a standalone copy of this script (built by
#   `npm run build-installer`), or paste this into PowerShell:
#     irm https://raw.githubusercontent.com/marcvef/wow-lefthytools/main/install.ps1 | iex
#   It downloads the latest LefthyTools from GitHub and installs it into WoW: Forever's AddOns
#   folder. Run it again any time to update. Settings are kept (they live in the WTF folder).
#
# Development, from a clone of the repo:
#   .\install.ps1             install this checkout's LefthyTools folder
#   .\install.ps1 -Link       junction AddOns\LefthyTools to this checkout (edits only need /reload)
#   .\install.ps1 -Download   install the latest version from GitHub instead
#   -GameDir <dir>            the WoW: Forever folder (...\World of Warcraft\_classic_beta_)
#   -Force                    reinstall even if that version is already installed
#
# Versions: the TOC holds the base version (e.g. 0.3.0, tagged v0.3.0). The installed copy gets the
# exact build written into its TOC, like `git describe`: 0.3.0 for the tagged commit itself,
# 0.3.0-4-g1a2b3c4 four commits later. The addon shows it with /lefthy version.
param(
	[string]$GameDir,
	[switch]$Link,
	[switch]$Download,
	[switch]$Force
)

# Everything runs in its own scope, so pasting this into a PowerShell window leaves no settings behind.
& {
	param($GameDir, $Link, $Download, $Force, $ScriptRoot)
	$ErrorActionPreference = 'Stop'
	$ProgressPreference = 'SilentlyContinue' # the progress bar makes downloads very slow in PowerShell 5
	[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 # TLS 1.2

	$Repo = 'marcvef/wow-lefthytools'
	$Name = 'LefthyTools'
	$Flavor = '_classic_beta_' # WoW: Forever's folder inside the World of Warcraft install
	$Legacy = @('Mirage')      # addons that are now part of LefthyTools; left installed they'd run twice
	$Remembered = Join-Path $env:LOCALAPPDATA 'LefthyTools\game-folder.txt'

	function Test-ForeverFolder([string]$dir) {
		if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return $false }
		foreach ($marker in 'Interface', 'WowB.exe', 'Wow.exe', '.flavor.info') {
			if (Test-Path -LiteralPath (Join-Path $dir $marker)) { return $true }
		}
		return $false
	}

	# Accepts the World of Warcraft folder or the Forever folder itself.
	function Resolve-ForeverFolder([string]$dir) {
		if (-not $dir) { return $null }
		$dir = $dir.Trim().Trim('"')
		$inner = Join-Path $dir $Flavor
		if (Test-ForeverFolder $inner) { return $inner }
		if ((Split-Path $dir -Leaf) -eq $Flavor -and (Test-ForeverFolder $dir)) { return $dir }
		return $null
	}

	function Find-ForeverFolder {
		$candidates = New-Object System.Collections.Generic.List[string]
		if (Test-Path -LiteralPath $Remembered) { $candidates.Add((Get-Content -LiteralPath $Remembered -TotalCount 1)) }
		# Battle.net's own list of installs (product.db holds the paths as plain text).
		$db = Join-Path $env:ProgramData 'Battle.net\Agent\product.db'
		if (Test-Path -LiteralPath $db) {
			$text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($db))
			foreach ($m in [regex]::Matches($text, '[A-Za-z]:[\\/][^\x00-\x1f"<>|*?]*?World of Warcraft')) { $candidates.Add($m.Value) }
		}
		# The usual places on every local drive.
		foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
			foreach ($parent in '', 'Games', 'Program Files (x86)', 'Program Files', 'Blizzard', 'Games\Blizzard', 'Battle.net') {
				$candidates.Add((Join-Path (Join-Path $drive.Root $parent) 'World of Warcraft'))
			}
		}
		foreach ($candidate in $candidates) {
			$found = Resolve-ForeverFolder $candidate
			if ($found) { return $found }
		}
		return $null
	}

	function Get-TocVersion([string]$toc) {
		$line = Select-String -LiteralPath $toc -Pattern '^## Version:\s*(.+?)\s*$' | Select-Object -First 1
		if ($line) { return $line.Matches[0].Groups[1].Value }
		return $null
	}

	# The files a TOC loads (every line that isn't empty or a comment).
	function Get-TocFiles([string]$toc) {
		if (-not (Test-Path -LiteralPath $toc)) { return @() }
		return @([IO.File]::ReadAllLines($toc) | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() })
	}

	function Set-TocVersion([string]$toc, [string]$version) {
		$lines = [IO.File]::ReadAllLines($toc) | ForEach-Object { if ($_ -match '^## Version:') { "## Version: $version" } else { $_ } }
		[IO.File]::WriteAllLines($toc, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
	}

	function Format-Version([string]$base, $count, [string]$sha) {
		if ($count -eq 0) { return $base }
		$hash = if ($sha) { 'g' + $sha.Substring(0, 7) } else { 'gunknown' }
		if ($null -ne $count) { return "$base-$count-$hash" }
		return "$base-$hash"
	}

	# git writes to stderr for harmless things; in PowerShell 5 that would stop the script.
	function Invoke-Git {
		if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
		$old = $ErrorActionPreference
		$ErrorActionPreference = 'Continue'
		try {
			$out = & git @args 2>$null
			if ($LASTEXITCODE -eq 0) { return $out }
			return $null
		} finally {
			$ErrorActionPreference = $old
		}
	}

	# git archive stores the commit id as the zip file's comment.
	function Get-ZipComment([string]$zip) {
		$bytes = [IO.File]::ReadAllBytes($zip)
		for ($i = $bytes.Length - 22; $i -ge [Math]::Max(0, $bytes.Length - 65557); $i--) {
			if ($bytes[$i] -eq 0x50 -and $bytes[$i + 1] -eq 0x4b -and $bytes[$i + 2] -eq 5 -and $bytes[$i + 3] -eq 6) {
				$length = $bytes[$i + 20] + 256 * $bytes[$i + 21]
				$comment = [Text.Encoding]::ASCII.GetString($bytes, $i + 22, $length)
				if ($comment -match '^[0-9a-f]{40}$') { return $comment }
				return $null
			}
		}
		return $null
	}

	function Get-Latest([string]$temp) {
		Write-Host 'Downloading the latest LefthyTools from GitHub...'
		$sha = $null
		try { $sha = (Invoke-RestMethod "https://api.github.com/repos/$Repo/commits/main" -TimeoutSec 20).sha } catch { }
		$ref = if ($sha) { $sha } else { 'refs/heads/main' }
		$zip = Join-Path $temp 'download.zip'
		Invoke-WebRequest "https://codeload.github.com/$Repo/zip/$ref" -OutFile $zip -UseBasicParsing -TimeoutSec 120
		if (-not $sha) { $sha = Get-ZipComment $zip }
		Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $temp 'repo')
		$root = Get-ChildItem -LiteralPath (Join-Path $temp 'repo') -Directory | Select-Object -First 1
		$addon = Join-Path $root.FullName $Name
		$toc = Join-Path $addon "$Name.toc"
		if (-not (Test-Path -LiteralPath $toc)) { throw "The download doesn't contain $Name\$Name.toc." }
		$base = Get-TocVersion $toc
		$count = $null
		if ($sha) {
			try { $count = [int](Invoke-RestMethod "https://api.github.com/repos/$Repo/compare/v$base...$sha" -TimeoutSec 20).ahead_by } catch { }
		}
		return @{ Addon = $addon; Version = (Format-Version $base $count $sha) }
	}

	function Get-Local([string]$root) {
		$addon = Join-Path $root $Name
		$base = Get-TocVersion (Join-Path $addon "$Name.toc")
		$version = "$base-dev"
		$describe = Invoke-Git -C $root describe --tags --long --dirty --match 'v[0-9]*'
		if ($describe -match '^v(.+)-(\d+)-g([0-9a-f]+)(-dirty)?$') {
			$version = if ($Matches[2] -eq '0' -and -not $Matches[4]) { $Matches[1] } else { "$($Matches[1])-$($Matches[2])-g$($Matches[3])$($Matches[4])" }
		} else {
			$hash = Invoke-Git -C $root rev-parse --short=7 HEAD
			if ($hash) { $version = "$base-g$hash" }
		}
		return @{ Addon = $addon; Version = $version }
	}

	function Remove-AddonFolder([string]$path) {
		if (-not (Test-Path -LiteralPath $path)) { return }
		$item = Get-Item -LiteralPath $path -Force
		if ($item.LinkType) {
			cmd /c rmdir "$path" | Out-Null # removes only the junction, never the files it points to
		} else {
			Remove-Item -LiteralPath $path -Recurse -Force
		}
	}

	# --- Where is WoW: Forever? ---
	$game = $null
	if ($GameDir) {
		$game = Resolve-ForeverFolder $GameDir
		if (-not $game -and (Test-ForeverFolder $GameDir)) { $game = $GameDir }
		if (-not $game) { throw "Not a WoW: Forever folder: $GameDir" }
	} else {
		$game = Find-ForeverFolder
	}
	while (-not $game) {
		Write-Host "WoW: Forever wasn't found. Paste the path of your 'World of Warcraft' folder" -ForegroundColor Yellow
		$answer = Read-Host '(empty to cancel)'
		if (-not $answer) { throw 'Cancelled.' }
		$game = Resolve-ForeverFolder $answer
		if (-not $game) { Write-Host "No '$Flavor' folder in there." -ForegroundColor Yellow }
	}
	New-Item -ItemType Directory -Force (Split-Path $Remembered) | Out-Null
	Set-Content -LiteralPath $Remembered -Value $game -Encoding UTF8

	# --- What to install ---
	$isCheckout = $ScriptRoot -and (Test-Path -LiteralPath (Join-Path $ScriptRoot "$Name\$Name.toc"))
	if ($Link -and (-not $isCheckout -or $Download)) { throw '-Link only works from a clone of the repo.' }
	$temp = Join-Path ([IO.Path]::GetTempPath()) ('LefthyTools-' + [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $temp | Out-Null
	try {
		$build = if ($Download -or -not $isCheckout) { Get-Latest $temp } else { Get-Local $ScriptRoot }

		$addons = Join-Path $game 'Interface\AddOns'
		New-Item -ItemType Directory -Force $addons | Out-Null
		foreach ($old in $Legacy) {
			$oldPath = Join-Path $addons $old
			if (Test-Path -LiteralPath $oldPath) {
				Remove-AddonFolder $oldPath
				Write-Host "Removed the old standalone addon: $old"
			}
		}

		$target = Join-Path $addons $Name
		$targetToc = Join-Path $target "$Name.toc"
		$installed = if ((Test-Path -LiteralPath $targetToc) -and -not (Get-Item -LiteralPath $target -Force).LinkType) { Get-TocVersion $targetToc } else { $null }
		if (-not $Force -and -not $Link -and $installed -eq $build.Version -and $build.Version -notmatch 'dirty|dev') {
			Write-Host "LefthyTools $installed is already the latest version." -ForegroundColor Green
			return
		}

		# The game only loads files that are new to the TOC after a restart (a /reload into such an
		# update can even freeze the client), so say so when there are any.
		$oldFiles = if ($installed) { Get-TocFiles $targetToc } else { $null }
		Remove-AddonFolder $target
		if ($Link) {
			New-Item -ItemType Junction -Path $target -Target $build.Addon | Out-Null
			Write-Host "Linked $target -> $($build.Addon)"
		} else {
			Copy-Item -LiteralPath $build.Addon -Destination $target -Recurse
			Set-TocVersion $targetToc $build.Version
			$from = if ($installed) { "$installed -> " } else { '' }
			Write-Host "LefthyTools $from$($build.Version) installed in $target" -ForegroundColor Green
		}
		$added = if ($null -ne $oldFiles) { @(Get-TocFiles $targetToc | Where-Object { $oldFiles -notcontains $_ }) } else { @() }
		if ($added.Count -gt 0) {
			Write-Host "This update adds files ($($added -join ', ')): restart the game, a /reload is not enough." -ForegroundColor Yellow
		} else {
			Write-Host 'In game, type /reload. If something seems missing afterwards, restart the game once.'
		}
	} finally {
		Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
	}
} -GameDir $GameDir -Link $Link -Download $Download -Force $Force `
	-ScriptRoot $(if ($PSScriptRoot) { $PSScriptRoot } else { $env:LEFTHYTOOLS_INSTALLER_DIR }) # set by the .cmd
