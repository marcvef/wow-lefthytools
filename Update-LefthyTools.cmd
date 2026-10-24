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
#   `npm run build-installer`; it updates itself: a newer one on GitHub runs instead and replaces it),
#   or paste this into PowerShell:
#     irm https://raw.githubusercontent.com/marcvef/wow-lefthytools/main/install.ps1 | iex
#   It downloads the latest LefthyTools from GitHub and installs it into WoW: Forever's AddOns
#   folder (the release's, and the beta's too while both are installed). Run it again any time to
#   update. Settings are kept (they live in the WTF folder).
#
# Development, from a clone of the repo:
#   .\install.ps1             install this checkout's LefthyTools folder (and LefthyTools_DropData)
#   .\install.ps1 -Link       junction AddOns\LefthyTools (and the rest) to this checkout (edits only need /reload)
#   .\install.ps1 -Download   install the latest version from GitHub instead
#   -GameDir <dir>            the World of Warcraft folder (...\World of Warcraft), or one WoW: Forever
#                             folder in it for that folder alone (...\World of Warcraft\_forever_)
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
	# WoW: Forever's folders inside the World of Warcraft install: the release and the beta. Which
	# folders hold Forever, the game itself says (Get-ForeverGame); these names are the fallback.
	$KnownFlavors = @('_forever_', '_classic_beta_')
	$Legacy = @('Mirage') # addons that are now part of LefthyTools; left installed they'd run twice
	# Add-ons that come with it, each a folder of its own next to LefthyTools in the repo: the drop
	# database (GPL v3 like its source, so apart from the BSD-licensed rest).
	$Companions = @('LefthyTools_DropData')
	$Remembered = Join-Path $env:LOCALAPPDATA 'LefthyTools\game-folder.txt'

	# Any game folder (also just an Interface folder): what -GameDir may name when it isn't recognised.
	function Test-GameFolder([string]$dir) {
		if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return $false }
		foreach ($marker in 'Interface', 'WowB.exe', 'Wow.exe', '.flavor.info') {
			if (Test-Path -LiteralPath (Join-Path $dir $marker)) { return $true }
		}
		return $false
	}

	# The game is installed there (not just an Interface folder left behind). Not Interface: the
	# release has none until its first start.
	function Test-GameInstalled([string]$dir) {
		foreach ($marker in 'WowB.exe', 'Wow.exe', '.flavor.info') {
			if (Test-Path -LiteralPath (Join-Path $dir $marker)) { return $true }
		}
		return $false
	}

	# Each installed product's client version (product -> version) from a World of Warcraft folder's
	# .build.info, or $null without a readable one. It's a table: a header of typed column names
	# (Branch!STRING:0|Active!DEC:1|...|Version!STRING:0|...|Product!STRING:0), then a row per
	# product (us|1|...|1.60.1.70450|...|wowf), so columns are looked up by name.
	function Get-ProductVersions([string]$root) {
		$path = Join-Path $root '.build.info'
		if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
		try { $lines = @([IO.File]::ReadAllLines($path) | Where-Object { $_.Trim() }) } catch { return $null }
		if ($lines.Count -eq 0) { return $null }
		$columns = @($lines[0].Split('|') | ForEach-Object { $_.Split('!')[0].Trim() })
		$version = [array]::IndexOf($columns, 'Version')
		$product = [array]::IndexOf($columns, 'Product')
		if ($version -lt 0 -or $product -lt 0) { return $null }
		$versions = @{}
		foreach ($line in @($lines | Select-Object -Skip 1)) {
			$cells = $line.Split('|')
			if ($cells.Count -le [Math]::Max($version, $product)) { continue }
			$name = $cells[$product].Trim()
			if ($name -and -not $versions.ContainsKey($name)) { $versions[$name] = $cells[$version].Trim() }
		}
		return $versions
	}

	# The product a game folder holds, from its .flavor.info (a header line, then e.g. wowf), or $null.
	function Get-FlavorProduct([string]$dir) {
		$path = Join-Path $dir '.flavor.info'
		if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
		try { $lines = [IO.File]::ReadAllLines($path) } catch { return $null }
		foreach ($line in $lines) {
			if ($line.Trim() -and $line -notmatch '!') { return $line.Trim() }
		}
		return $null
	}

	# A game folder: its path, product and kind. A beta, PTR or other test version says so in its
	# product (wow_classic_beta), else in the folder's name; anything else is the release (wowf).
	function New-Game([string]$dir, [string]$product) {
		$full = (Get-Item -LiteralPath $dir).FullName.TrimEnd('\')
		$label = if ($product) { $product } else { Split-Path $full -Leaf }
		$kind = if ($label -match 'beta|ptr|alpha|test') { 'beta' } else { 'release' }
		return [pscustomobject]@{ Path = $full; Product = $product; Kind = $kind }
	}

	# The game in $dir if it's WoW: Forever, else nothing. The World of Warcraft folder's .build.info
	# ($versions, from Get-ProductVersions) says so: Forever's client line is 1.60 (1.6x; Classic
	# Era is 1.15, the other flavors 2 and up), so a renamed folder still counts. When it doesn't
	# list the folder's product (no .build.info, no .flavor.info), the known folder names do.
	function Get-ForeverGame([string]$dir, $versions) {
		if (-not (Test-GameInstalled $dir)) { return }
		$product = Get-FlavorProduct $dir
		if ($null -ne $versions -and $product -and $versions.ContainsKey($product)) {
			if ($versions[$product] -notmatch '^1\.6') { return }
		} elseif ($KnownFlavors -notcontains (Split-Path $dir -Leaf)) {
			return
		}
		New-Game $dir $product
	}

	# The WoW: Forever folders in a World of Warcraft folder (among its _name_ folders).
	function Get-ForeverGamesIn([string]$root) {
		$versions = Get-ProductVersions $root
		foreach ($sub in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
			if ($sub.Name -notmatch '^_.+_$') { continue }
			$game = Get-ForeverGame $sub.FullName $versions
			if ($game) { $game }
		}
	}

	# A path as given (pasted, remembered): no quotes, no trailing backslash.
	function Get-CleanPath([string]$dir) {
		if (-not $dir) { return '' }
		$dir = $dir.Trim().Trim('"')
		if ($dir.Length -gt 3) { $dir = $dir.TrimEnd('\', '/') }
		return $dir
	}

	# Accepts the World of Warcraft folder (the Forever folders in it) or a Forever folder itself.
	function Resolve-ForeverGames([string]$dir) {
		$dir = Get-CleanPath $dir
		if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return }
		$inside = @(Get-ForeverGamesIn $dir)
		if ($inside.Count -gt 0) { return $inside }
		$parent = Split-Path $dir -Parent
		$versions = if ($parent) { Get-ProductVersions $parent } else { $null }
		$game = Get-ForeverGame $dir $versions
		if ($game) { $game }
	}

	# When it was last played: the newest of the files the game writes (settings, logs).
	function Get-LastPlayed([string]$dir) {
		$newest = [datetime]::MinValue
		foreach ($path in 'WTF\Config.wtf', 'Logs', 'WTF\Account', 'Cache') {
			$item = Get-Item -LiteralPath (Join-Path $dir $path) -ErrorAction SilentlyContinue
			if ($item -and $item.LastWriteTime -gt $newest) { $newest = $item.LastWriteTime }
		}
		return $newest
	}

	# Whether a drive (or network share) answers: $true, $false (no disk in it, no such drive) or
	# $null (no answer in time). A network drive that's disconnected or slow can keep every look at
	# it waiting for half a minute or more, so each drive is asked once, on a thread of its own
	# (Start-DriveCheck asks several at once), and gets $Wait seconds from then.
	$Wait = 10
	$asked = @{}
	function Start-DriveCheck([string]$root) {
		if ($asked.ContainsKey($root)) { return }
		$exists = [IO.DirectoryInfo].GetProperty('Exists').GetGetMethod()
		$task = New-Object 'Threading.Tasks.Task[bool]' ([Delegate]::CreateDelegate([Func[bool]], (New-Object IO.DirectoryInfo $root), $exists))
		$task.Start()
		$asked[$root] = @{ Task = $task; Until = [datetime]::UtcNow.AddSeconds($Wait) }
	}
	function Test-DriveAnswers([string]$root) {
		Start-DriveCheck $root
		$ask = $asked[$root]
		$ms = [Math]::Max(0, ($ask.Until - [datetime]::UtcNow).TotalMilliseconds)
		if (-not $ask.Task.Wait([int]$ms)) { return $null }
		return $ask.Task.Result
	}

	# Whether a path's drive answers (see Test-DriveAnswers); one that doesn't is noted in $skipped.
	function Test-Reachable([string]$path, $skipped) {
		try { $root = [IO.Path]::GetPathRoot($path) } catch { return $false }
		if (-not $root) { return $true }
		$answer = Test-DriveAnswers $root
		if ($null -eq $answer -and -not $skipped.Contains($root)) { $skipped[$root] = "no answer within $Wait s" }
		return [bool]$answer
	}

	# Adds the WoW: Forever folders among $candidates to $found, each once. A candidate on a drive
	# that doesn't answer is left out (and noted in $skipped).
	function Add-ForeverGames($candidates, $found, $skipped) {
		$seen = @{}
		foreach ($candidate in $candidates) {
			$candidate = Get-CleanPath $candidate
			if (-not $candidate -or $seen.ContainsKey($candidate)) { continue }
			$seen[$candidate] = $true
			if (-not (Test-Reachable $candidate $skipped)) { continue }
			foreach ($game in @(Resolve-ForeverGames $candidate)) {
				if (-not ($found | Where-Object { $_.Path -eq $game.Path })) { $found.Add($game) }
			}
		}
	}

	# Whether the World of Warcraft folder $root holds another WoW: Forever besides $game: by its
	# .build.info ($versions; one small file), or without one by the known folder names.
	function Test-OtherForever($game, [string]$root, $versions) {
		if ($null -ne $versions) {
			foreach ($product in @($versions.Keys)) {
				if ($product -ne $game.Product -and $versions[$product] -match '^1\.6') { return $true }
			}
			return $false
		}
		foreach ($name in $KnownFlavors) {
			if ($name -eq (Split-Path $game.Path -Leaf)) { continue }
			$dir = Join-Path $root $name
			if ((Test-Path -LiteralPath $dir -PathType Container) -and (Test-GameInstalled $dir)) { return $true }
		}
		return $false
	}

	# The folders to install into: one of each kind, the release and the beta (before launch the
	# beta is played and the release can't start yet; after it, the release is played), so one
	# update keeps both current while both are installed. With more than one copy of a kind (an old
	# copy, a second drive), the one played most recently, and all are listed: an update into a
	# folder the game doesn't use changes nothing in game.
	function Select-Games($found) {
		foreach ($kind in 'release', 'beta') {
			$copies = @($found | Where-Object { $_.Kind -eq $kind })
			if ($copies.Count -eq 0) { continue }
			if ($copies.Count -eq 1) { $copies[0]; continue }
			$best = $copies | Sort-Object { Get-LastPlayed $_.Path } -Descending | Select-Object -First 1
			Write-Host "WoW: Forever ($kind) was found in more than one place:" -ForegroundColor Yellow
			foreach ($copy in $copies) {
				$played = Get-LastPlayed $copy.Path
				$when = if ($played -eq [datetime]::MinValue) { 'not played yet' } else { 'last played {0:yyyy-MM-dd HH:mm}' -f $played }
				$mark = if ($copy.Path -eq $best.Path) { '  <- played most recently, installing here' } else { '' }
				Write-Host ("  {0}  ({1}){2}" -f $copy.Path, $when, $mark)
			}
			Write-Host 'Another one? Run it again with -GameDir "<that folder>".'
			$best
		}
	}

	# The WoW: Forever folders to install into. The remembered one (installed into last time) alone,
	# while the game is still there (not just an Interface folder left behind) and its World of
	# Warcraft folder holds no other Forever (.build.info); with another one there (the release next
	# to the beta), every Forever folder in it. Otherwise also Battle.net's list of installs and the
	# usual places on every fixed and USB drive; network drives aren't searched (a disconnected one
	# can take minutes to say so), and a drive that doesn't answer in time is left out.
	function Find-ForeverGames {
		$found = New-Object System.Collections.Generic.List[object]
		$skipped = [ordered]@{}
		$candidates = New-Object System.Collections.Generic.List[string]
		$remembered = if (Test-Path -LiteralPath $Remembered) { Get-CleanPath (Get-Content -LiteralPath $Remembered -TotalCount 1) } else { '' }
		if ($remembered -and (Test-Reachable $remembered $skipped) -and (Test-Path -LiteralPath $remembered -PathType Container)) {
			$root = Split-Path $remembered -Parent
			$versions = if ($root) { Get-ProductVersions $root } else { $null }
			$game = Get-ForeverGame $remembered $versions
			if ($game) {
				if (-not $root -or -not (Test-OtherForever $game $root $versions)) { return $game }
				return Select-Games @(Get-ForeverGamesIn $root)
			}
			# No longer Forever (or only an Interface folder is left): look next to it as well.
			$candidates.Add($remembered)
			if ($root) { $candidates.Add($root) }
		}
		# Battle.net's own list of installs (product.db holds the paths as plain text).
		$db = Join-Path $env:ProgramData 'Battle.net\Agent\product.db'
		if (Test-Path -LiteralPath $db) {
			$text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($db))
			foreach ($m in [regex]::Matches($text, '[A-Za-z]:[\\/][^\x00-\x1f"<>|*?]*?World of Warcraft')) { $candidates.Add($m.Value) }
		}
		# The usual places on every fixed and USB drive, all drives asked at once.
		$drives = New-Object System.Collections.Generic.List[string]
		foreach ($drive in [IO.DriveInfo]::GetDrives()) {
			$type = "$($drive.DriveType)" # known without asking the drive
			if ($type -eq 'Network') {
				if (-not $skipped.Contains($drive.Name)) { $skipped[$drive.Name] = 'network drive' }
			} elseif ('Fixed', 'Removable', 'Ram' -contains $type) {
				$drives.Add($drive.Name)
				Start-DriveCheck $drive.Name
			}
		}
		foreach ($root in $drives) {
			foreach ($parent in '', 'Games', 'Program Files (x86)', 'Program Files', 'Blizzard', 'Games\Blizzard', 'Battle.net') {
				$candidates.Add([IO.Path]::Combine($root, $parent, 'World of Warcraft'))
			}
		}
		Add-ForeverGames $candidates $found $skipped
		if ($skipped.Count -gt 0) {
			Write-Host ('Not searched: ' + (@($skipped.Keys | ForEach-Object { "$_ ($($skipped[$_]))" }) -join ', ') + '.')
		}
		Select-Games $found
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

	# The saved variables a TOC names (## SavedVariables and ## SavedVariablesPerCharacter). The game
	# reads them only at startup too: a new one isn't loaded or saved until a restart.
	function Get-TocSaved([string]$toc) {
		if (-not (Test-Path -LiteralPath $toc)) { return @() }
		$names = New-Object System.Collections.Generic.List[string]
		foreach ($line in [IO.File]::ReadAllLines($toc)) {
			if ($line -match '^##\s*SavedVariables(PerCharacter)?\s*:(.*)$') {
				foreach ($name in $Matches[2].Split(',')) {
					if ($name.Trim()) { $names.Add($name.Trim()) }
				}
			}
		}
		return @($names)
	}

	# After copying: every file of the download arrived intact (same SHA-256; the TOC is left out,
	# its version line is stamped on install) and every file the TOC loads is there.
	function Test-Install([string]$source, [string]$target, [string]$addon = $Name) {
		$problems = New-Object System.Collections.Generic.List[string]
		$root = (Get-Item -LiteralPath $source).FullName.TrimEnd('\')
		$count = 0
		foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
			$count++
			$relative = $file.FullName.Substring($root.Length + 1)
			$copy = Join-Path $target $relative
			if (-not (Test-Path -LiteralPath $copy -PathType Leaf)) {
				$problems.Add("missing: $relative")
			} elseif ($relative -ne "$addon.toc") {
				$want = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
				$have = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash
				if ($want -ne $have) { $problems.Add("damaged: $relative") }
			}
		}
		foreach ($entry in Get-TocFiles (Join-Path $target "$addon.toc")) {
			if (-not (Test-Path -LiteralPath (Join-Path $target $entry) -PathType Leaf)) {
				$problems.Add("in the TOC but not installed: $entry")
			}
		}
		return @{ Problems = $problems; Count = $count }
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

	# --- A newer installer? ---
	# Started from Update-LefthyTools.cmd (not from a clone of the repo, and not already the newer one):
	# when GitHub has a different .cmd, that one runs instead, so nobody needs to be sent a new file
	# again. This file is replaced with it too (passed on, it's the newest), but only when its batch
	# header is byte for byte the same: cmd.exe is still reading this file and goes on at the same
	# place once PowerShell is done. No GitHub: this one carries on.
	$installer = $env:LEFTHYTOOLS_INSTALLER
	$fromCmd = $installer -and (Test-Path -LiteralPath $installer -PathType Leaf) -and -not $env:LEFTHYTOOLS_SELF_UPDATED -and -not $Link -and
		-not ($ScriptRoot -and (Test-Path -LiteralPath (Join-Path $ScriptRoot "$Name\$Name.toc")))
	if ($fromCmd) {
		$latest = $null
		try {
			$sha = $null
			try { $sha = (Invoke-RestMethod "https://api.github.com/repos/$Repo/commits/main" -TimeoutSec 20).sha } catch { }
			$ref = if ($sha) { $sha } else { 'main' }
			$latest = (Invoke-WebRequest "https://raw.githubusercontent.com/$Repo/$ref/Update-LefthyTools.cmd" -UseBasicParsing -TimeoutSec 30).Content
			if ($latest -is [byte[]]) { $latest = [Text.Encoding]::UTF8.GetString($latest) }
		} catch { $latest = $null }
		$mine = [IO.File]::ReadAllText($installer)
		if ($latest -is [string] -and $latest.StartsWith('<# : LefthyTools installer') -and $latest -ne $mine) {
			Write-Host 'There is a newer installer: using it.'
			$header = $mine.IndexOf("#>`r`n")
			if ($header -gt 0 -and $latest.Length -gt $header + 4 -and $latest.Substring(0, $header + 4) -eq $mine.Substring(0, $header + 4)) {
				try {
					[IO.File]::WriteAllText($installer, $latest, (New-Object Text.UTF8Encoding $false))
					Write-Host "$(Split-Path $installer -Leaf) is now the newer one too (pass this file on)."
				} catch {
					Write-Host "Couldn't update $installer itself; it still works (it uses the newest installer each time)."
				}
			}
			$env:LEFTHYTOOLS_SELF_UPDATED = '1'
			try {
				$call = @{}
				if ($GameDir) { $call.GameDir = $GameDir }
				if ($Download) { $call.Download = $true }
				if ($Force) { $call.Force = $true }
				& ([ScriptBlock]::Create($latest)) @call
			} finally {
				Remove-Item Env:\LEFTHYTOOLS_SELF_UPDATED -ErrorAction SilentlyContinue
			}
			return
		}
	}
	# --- Where is WoW: Forever? ---
	$games = @()
	if ($GameDir) {
		$games = @(Resolve-ForeverGames $GameDir)
		$dir = Get-CleanPath $GameDir
		if ($games.Count -eq 0 -and (Test-GameFolder $dir)) { $games = @(New-Game $dir (Get-FlavorProduct $dir)) }
		if ($games.Count -eq 0) { throw "Not a WoW: Forever folder: $GameDir" }
		$games = @(Select-Games $games)
	} else {
		$games = @(Find-ForeverGames)
	}
	while ($games.Count -eq 0) {
		Write-Host "WoW: Forever wasn't found. Paste the path of your 'World of Warcraft' folder" -ForegroundColor Yellow
		$answer = Read-Host '(empty to cancel)'
		if (-not $answer) { throw 'Cancelled.' }
		$games = @(Select-Games @(Resolve-ForeverGames $answer))
		if ($games.Count -eq 0) { Write-Host 'No WoW: Forever folder in there.' -ForegroundColor Yellow }
	}
	if ($games.Count -gt 1) {
		Write-Host "WoW: Forever's release and beta are both installed: installing into both, so one update keeps both current."
		foreach ($game in $games) { Write-Host "  $($game.Path)  ($($game.Kind))" }
	}
	# The release from then on, while there is one.
	$keep = @(@($games | Where-Object { $_.Kind -eq 'release' }) + $games)[0]
	New-Item -ItemType Directory -Force (Split-Path $Remembered) | Out-Null
	Set-Content -LiteralPath $Remembered -Value $keep.Path -Encoding UTF8

	# --- What to install ---
	$isCheckout = $ScriptRoot -and (Test-Path -LiteralPath (Join-Path $ScriptRoot "$Name\$Name.toc"))
	if ($Link -and (-not $isCheckout -or $Download)) { throw '-Link only works from a clone of the repo.' }
	$temp = Join-Path ([IO.Path]::GetTempPath()) ('LefthyTools-' + [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $temp | Out-Null
	try {
		$build = if ($Download -or -not $isCheckout) { Get-Latest $temp } else { Get-Local $ScriptRoot }
		# The add-ons that come with it, in this build.
		$sourceRoot = Split-Path $build.Addon -Parent
		$companions = @($Companions | Where-Object { Test-Path -LiteralPath (Join-Path $sourceRoot "$_\$_.toc") })
		$restart = New-Object System.Collections.Generic.List[string]
		$updated = $false

		foreach ($game in $games) {
			if ($games.Count -gt 1) {
				Write-Host ''
				Write-Host "WoW: Forever $($game.Kind), $($game.Path):"
			}
			# A folder the game hasn't started in yet (the release before launch) has no Interface
			# folder: it's made here.
			$addons = Join-Path $game.Path 'Interface\AddOns'
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
			# Which of the add-ons that come with it aren't installed here yet.
			$newCompanions = @($companions | Where-Object { -not (Test-Path -LiteralPath (Join-Path $addons "$_\$_.toc")) })
			if (-not $Force -and -not $Link -and $installed -eq $build.Version -and $build.Version -notmatch 'dirty|dev' -and $newCompanions.Count -eq 0) {
				Write-Host "LefthyTools $installed is already the latest version." -ForegroundColor Green
				continue
			}

			# The game only loads files that are new to the TOC after a restart (a /reload into such an
			# update can even freeze the client), and the same goes for new saved variables, so say so
			# when there are any.
			$oldFiles = if ($installed) { Get-TocFiles $targetToc } else { $null }
			$oldSaved = if ($installed) { Get-TocSaved $targetToc } else { $null }
			Remove-AddonFolder $target
			if ($Link) {
				New-Item -ItemType Junction -Path $target -Target $build.Addon | Out-Null
				Write-Host "Linked $target -> $($build.Addon)"
			} else {
				Copy-Item -LiteralPath $build.Addon -Destination $target -Recurse
				Set-TocVersion $targetToc $build.Version
				$check = Test-Install $build.Addon $target
				if ($check.Problems.Count -gt 0) {
					foreach ($problem in $check.Problems) { Write-Host "  $problem" -ForegroundColor Red }
					throw ("The installed files don't match the download ($($check.Problems.Count) problem(s)). Run it again;" +
						' if it keeps happening, an antivirus may be blocking files in the AddOns folder.')
				}
				$from = if ($installed) { "$installed -> " } else { '' }
				Write-Host "LefthyTools $from$($build.Version) installed in $target" -ForegroundColor Green
			}
			$files = if ($Link) { 0 } else { $check.Count }
			foreach ($companion in $companions) {
				$from = Join-Path $sourceRoot $companion
				$to = Join-Path $addons $companion
				Remove-AddonFolder $to
				if ($Link) {
					New-Item -ItemType Junction -Path $to -Target $from | Out-Null
					Write-Host "Linked $to -> $from"
				} else {
					Copy-Item -LiteralPath $from -Destination $to -Recurse
					$check = Test-Install $from $to $companion
					if ($check.Problems.Count -gt 0) {
						foreach ($problem in $check.Problems) { Write-Host "  $companion\$problem" -ForegroundColor Red }
						throw ("The installed files don't match the download ($($check.Problems.Count) problem(s)). Run it again;" +
							' if it keeps happening, an antivirus may be blocking files in the AddOns folder.')
					}
					$files += $check.Count
					Write-Host "$companion installed with it in $to"
				}
			}
			if (-not $Link) {
				Write-Host "Checked: all $files files arrived intact (SHA-256), and every file the game loads is there."
			}
			$updated = $true
			$added = if ($null -ne $oldFiles) { @(Get-TocFiles $targetToc | Where-Object { $oldFiles -notcontains $_ }) } else { @() }
			$addedSaved = if ($null -ne $oldSaved) { @(Get-TocSaved $targetToc | Where-Object { $oldSaved -notcontains $_ }) } else { @() }
			$why = if ($installed -and $newCompanions.Count -gt 0) {
				"This update adds an add-on ($($newCompanions -join ', ')): restart the game, a /reload is not enough."
			} elseif ($added.Count -gt 0) {
				"This update adds files ($($added -join ', ')): restart the game, a /reload is not enough."
			} elseif ($addedSaved.Count -gt 0) {
				"This update adds saved data ($($addedSaved -join ', ')): restart the game, a /reload is not enough."
			} else { $null }
			if ($why -and -not $restart.Contains($why)) { $restart.Add($why) }
		}

		if ($updated) {
			if ($games.Count -gt 1) { Write-Host '' }
			if ($restart.Count -gt 0) {
				foreach ($why in $restart) { Write-Host $why -ForegroundColor Yellow }
			} else {
				Write-Host 'In game, type /reload. If something seems missing afterwards, restart the game once.'
			}
			if (-not $Link) {
				Write-Host "Check in game: /lefthy version should say $($build.Version)."
			}
		}
	} finally {
		Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
	}
} -GameDir $GameDir -Link $Link -Download $Download -Force $Force `
	-ScriptRoot $(if ($PSScriptRoot) { $PSScriptRoot } else { $env:LEFTHYTOOLS_INSTALLER_DIR }) # set by the .cmd
