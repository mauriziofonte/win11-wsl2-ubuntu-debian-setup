# Unit tests of the WSL settings that install/win11.ps1 computes: the three resource profiles (against the
# tables of both guides), the swap, the disk limit it proposes, and the .wslconfig merge.
#
#   pwsh tests/powershell/unit.ps1          # also in Windows PowerShell 5.1: powershell -File ...
#
# Output: one "ok" or "not ok" line per check; exit status 1 when a check fails.
#
# Author: Maurizio Fonte (https://www.mauriziofonte.it)
# License: MIT License

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Import-Win11Function.ps1")
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$script:count = 0
$script:failed = 0

function Test-Equal {
    param ([String]$Name, $Expected, $Actual)
    $script:count++
    $want = ($Expected | ForEach-Object { "$_" }) -join "`n"
    $got = ($Actual | ForEach-Object { "$_" }) -join "`n"
    if ($want -ceq $got) {
        Write-Host "ok $($script:count) - $Name"
    }
    else {
        $script:failed++
        Write-Host "not ok $($script:count) - $Name"
        Write-Host "#   expected: $($want -replace "`n", "`n#             ")"
        Write-Host "#   got:      $($got -replace "`n", "`n#             ")"
    }
}

# --- Profiles: the rows of the table after "<!-- ci:profiles -->" in each guide.
foreach ($guide in @("docs/en/SETUP-EN.md", "docs/it/SETUP-IT.md")) {
    $lines = Get-Content -LiteralPath (Join-Path $repo $guide) -Encoding UTF8
    $at = [Array]::IndexOf($lines, "<!-- ci:profiles -->")
    Test-Equal "$guide has the profile table" $true ($at -ge 0)
    if ($at -lt 0) { continue }
    $rows = 0
    for ($i = $at + 1; $i -lt $lines.Count -and $lines[$i].StartsWith("|"); $i++) {
        $cells = @($lines[$i].Trim("|").Split("|") | ForEach-Object { $_.Trim() })
        if ($cells[0] -notmatch '^(\d+) GB \((\d+[.,]\d+)\), (\d+)$') { continue }
        $installedGB = [Double]$Matches[1]
        $usableGB = [Double]($Matches[2] -replace ',', '.')
        $threads = [Int]$Matches[3]
        $want = @()
        foreach ($cell in $cells[1..3]) {
            $numbers = @([Regex]::Matches($cell, '\d+') | ForEach-Object { $_.Value })
            $want += ($numbers -join "/")
        }
        $got = @(Get-VmProfiles -InstalledGB $installedGB -UsableGB $usableGB -Threads $threads |
                ForEach-Object { "$($_.MemoryGB)/$($_.Processors)/$($_.SwapGB)" })
        Test-Equal "${guide}: profiles for $($cells[0])" $want $got
        $rows++
    }
    Test-Equal "${guide}: the profile table has 4 rows" 4 $rows
}
# --- The .wslconfig of the guides (the block after "<!-- ci:wslconfig -->"): what the setup writes for
# Balanced on a 32 GB PC with 16 logical processors, NAT, no WSLg, no disk limit. Comments aside: they are translated.
$balanced = Get-VmProfiles -InstalledGB 32 -UsableGB 31.4 -Threads 16 | Where-Object { $_.Name -eq "Balanced" }
$written = Merge-IniText -Text "" -Settings @(Get-WslSettings -MemoryGB $balanced.MemoryGB -Processors $balanced.Processors `
        -SwapGB $balanced.SwapGB -Networking "nat" -Gui $false -Base $true -VhdSizeGB 0)
$writtenKeys = @($written -split "`r`n" | Where-Object { $_ -and -not $_.StartsWith("#") })
foreach ($guide in @("docs/en/SETUP-EN.md", "docs/it/SETUP-IT.md")) {
    $lines = Get-Content -LiteralPath (Join-Path $repo $guide) -Encoding UTF8
    $at = [Array]::IndexOf($lines, "<!-- ci:wslconfig -->")
    $block = @()
    if ($at -ge 0 -and $lines[$at + 1] -eq '```ini') {
        for ($i = $at + 2; $i -lt $lines.Count -and $lines[$i] -ne '```'; $i++) { $block += $lines[$i] }
    }
    Test-Equal "${guide}: the .wslconfig example is what the setup writes" $writtenKeys @($block | Where-Object { $_ -and -not $_.StartsWith("#") })
    Test-Equal "${guide}: the .wslconfig example has a comment for each setting the setup comments" `
        @($written -split "`r`n" | Where-Object { $_.StartsWith("#") }).Count @($block | Where-Object { $_.StartsWith("#") }).Count
}

Test-Equal "profiles are named Light, Balanced, Performance" @("Light", "Balanced", "Performance") @(Get-VmProfiles -InstalledGB 16 -UsableGB 15.6 -Threads 8 | ForEach-Object { $_.Name })
Test-Equal "a 4 GB, 2-thread PC still gets 2 GB and 1 processor" @("2/1/1", "2/1/1", "2/1/1") @(Get-VmProfiles -InstalledGB 4 -UsableGB 3.8 -Threads 2 | ForEach-Object { "$($_.MemoryGB)/$($_.Processors)/$($_.SwapGB)" })

# --- Swap and disk limit.
Test-Equal "swap is half the RAM, from 1 to 8 GB" @(1, 1, 2, 4, 8, 8) @(1, 2, 4, 8, 16, 64 | ForEach-Object { Get-SwapGB -MemoryGB $_ })
Test-Equal "the disk limit proposed is half the space, rounded down to 512/256/128/64 GB" @(512, 512, 256, 128, 64, 50, 16) @(4000, 1100, 600, 300, 150, 100, 20 | ForEach-Object { Get-VhdProposal -AvailableGB $_ })

# --- .wslconfig.
$settings = @(Get-WslSettings -MemoryGB 8 -Processors 4 -SwapGB 4 -Networking "nat" -Gui $false -Base $true -VhdSizeGB 0)
Test-Equal "a new .wslconfig: the keys of the profile, NAT, no WSLg and the base set" @(
    "wsl2.memory=8GB", "wsl2.processors=4", "wsl2.swap=4GB", "wsl2.networkingMode=nat", "wsl2.guiApplications=false",
    "wsl2.maxCrashDumpCount=3", "experimental.sparseVhd=true", "experimental.autoMemoryReclaim=dropCache"
) @($settings | ForEach-Object { "$($_.Section).$($_.Key)=$($_.Value)" })
$mirrored = @(Get-WslSettings -MemoryGB $null -Processors $null -SwapGB $null -Networking "mirrored" -Gui $null -Base $false -VhdSizeGB 128)
Test-Equal "mirrored brings dnsTunneling, autoProxy and firewall; a limit brings defaultVhdSize; nothing else without -Base" @(
    "wsl2.networkingMode=mirrored", "wsl2.dnsTunneling=true", "wsl2.autoProxy=true", "wsl2.firewall=true", "wsl2.defaultVhdSize=128GB"
) @($mirrored | ForEach-Object { "$($_.Section).$($_.Key)=$($_.Value)" })
Test-Equal "no options and no -Base: no setting at all" 0 @(Get-WslSettings -MemoryGB $null -Processors $null -SwapGB $null -Networking "" -Gui $null -Base $false -VhdSizeGB 0).Count

$new = Merge-IniText -Text "" -Settings $settings
Test-Equal "a new file starts with [wsl2] and ends with CRLF" @($true, $true) @($new.StartsWith("[wsl2]`r`n# RAM of the WSL virtual machine`r`nmemory=8GB`r`n"), $new.EndsWith("dropCache`r`n"))
Test-Equal "a new file reads back as the settings" 0 @(Get-IniChange -Text $new -Settings $settings).Count

$mine = @(
    "# my settings",
    "[WSL2]",
    "Memory = 3GB",
    "kernelCommandLine = vsyscall=emulate",
    "",
    "[experimental]",
    "; mine too",
    "hostAddressLoopback=true"
) -join "`n"
$small = @(Get-WslSettings -MemoryGB 6 -Processors $null -SwapGB $null -Networking "mirrored" -Gui $null -Base $false -VhdSizeGB 0)
Test-Equal "the changes, as the installer shows them" @(
    "[wsl2] memory: 3GB -> 6GB", "[wsl2] networkingMode: - -> mirrored", "[wsl2] dnsTunneling: - -> true",
    "[wsl2] autoProxy: - -> true", "[wsl2] firewall: - -> true"
) @(Get-IniChange -Text $mine -Settings $small)
$merged = Merge-IniText -Text $mine -Settings $small
Test-Equal "an existing file keeps its comments, its other keys and sections; a key changes in place" @(
    "# my settings", "[WSL2]", "memory=6GB", "kernelCommandLine = vsyscall=emulate",
    "# nat: a private network behind Windows; mirrored: the network interfaces of Windows", "networkingMode=mirrored",
    "dnsTunneling=true", "autoProxy=true", "firewall=true", "", "[experimental]", "; mine too", "hostAddressLoopback=true"
) @($merged.TrimEnd("`r", "`n") -split "`r`n")
Test-Equal "merging again changes nothing" $merged (Merge-IniText -Text $merged -Settings $small)
Test-Equal "after the merge there is nothing left to change" 0 @(Get-IniChange -Text $merged -Settings $small).Count
$values = Read-IniValues -Text $merged
Test-Equal "Read-IniValues: lower-case section.key, the first value wins, comments skipped" @("6GB", "true", $false) @($values["wsl2.memory"], $values["experimental.hostaddressloopback"], $values.ContainsKey(".# my settings"))
$base = Merge-IniText -Text $mine -Settings @(Get-WslSettings -MemoryGB $null -Processors $null -SwapGB $null -Networking "" -Gui $null -Base $true -VhdSizeGB 0)
Test-Equal "a new key of an existing section goes after its last line" @("; mine too", "hostAddressLoopback=true", "# New virtual disks are sparse: space freed inside Linux goes back to Windows", "sparseVhd=true") @(($base -split "`r`n")[8..11])

Write-Host "1..$($script:count)"
if ($script:failed -gt 0) {
    Write-Host "# $($script:failed) of $($script:count) checks failed"
    exit 1
}
Write-Host "# all $($script:count) checks passed"
exit 0
