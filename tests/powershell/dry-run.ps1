# install/win11.ps1 -DryRun -Unattended in Windows PowerShell 5.1: the steps it would take, the .wslconfig
# changes it would make, and the options it refuses before changing anything.
#
#   pwsh tests/powershell/dry-run.ps1
#
# Each run gets its own %UserProfile%, so the .wslconfig of this machine is never read or written.
# Output: one "ok" or "not ok" line per check; exit status 1 when a check fails.
#
# Author: Maurizio Fonte (https://www.mauriziofonte.it)
# License: MIT License

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$setup = Join-Path $repo "install/win11.ps1"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "win11-dry-run"
$script:count = 0
$script:failed = 0

function Write-Result {
    param ([String]$Name, [Bool]$Passed, [String]$Detail = "")
    $script:count++
    if ($Passed) {
        Write-Host "ok $($script:count) - $Name"
        return
    }
    $script:failed++
    Write-Host "not ok $($script:count) - $Name"
    if ($Detail) { Write-Host ("#   " + ($Detail -replace "`n", "`n#   ")) }
}

# Runs win11.ps1 -DryRun -Unattended with these options and, if given, this .wslconfig already in place.
function Invoke-DryRun {
    param ([String[]]$Options, $WslConfig = $null)
    $profileDir = Join-Path $scratch ([Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    $config = Join-Path $profileDir ".wslconfig"
    if ($null -ne $WslConfig) { [IO.File]::WriteAllText($config, $WslConfig) }
    $saved = $env:USERPROFILE
    $env:USERPROFILE = $profileDir
    try {
        $output = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setup -DryRun -Unattended @Options 2>&1) -join "`n"
        $status = $LASTEXITCODE
    }
    finally {
        $env:USERPROFILE = $saved
    }
    $after = if (Test-Path -LiteralPath $config) { [IO.File]::ReadAllText($config) } else { $null }
    return [PSCustomObject]@{ Output = $output; Status = $status; Before = $WslConfig; After = $after }
}

function Test-Run {
    param ([String]$Name, $Run, [Int]$Status = 0, [String[]]$Contains = @(), [String[]]$Lacks = @())
    $problems = @()
    if ($Run.Status -ne $Status) { $problems += "exit status $($Run.Status), expected $Status" }
    foreach ($want in $Contains) { if (-not $Run.Output.Contains($want)) { $problems += "missing: $want" } }
    foreach ($unwanted in $Lacks) { if ($Run.Output.Contains($unwanted)) { $problems += "unexpected: $unwanted" } }
    if ($Run.After -cne $Run.Before) { $problems += ".wslconfig changed in a dry run" }
    $detail = if ($problems) { ($problems -join "`n") + "`n--- output:`n" + $Run.Output } else { "" }
    Write-Result $Name ($problems.Count -eq 0) $detail
}

# --- A new PC: every step, a new .wslconfig with the Balanced profile, NAT and the base set.
foreach ($distro in @("Debian", "Ubuntu-24.04", "Ubuntu-26.04")) {
    $run = Invoke-DryRun -Options @("-Distro", $distro, "-Shell", "zsh")
    Test-Run "$distro, no .wslconfig yet" $run -Contains @(
        "[8/8]", "Distribution: $distro", "Shell: zsh", "Virtual machine: Balanced", "Networking: nat", "Disk limit: none",
        "does not exist: it is created", "[wsl2] memory: - -> ", "[wsl2] networkingMode: - -> nat",
        "[wsl2] guiApplications: - -> false", "[experimental] sparseVhd: - -> true",
        "[experimental] autoMemoryReclaim: - -> dropCache", "--shell zsh", "$distro.lnk"
    ) -Lacks @("dnsTunneling", "defaultVhdSize")
}

# --- Every option given: they all reach .wslconfig, wsl.conf (through the stack installer) and wsl --install.
$run = Invoke-DryRun -Options @("-Distro", "Ubuntu-26.04", "-Shell", "fish", "-VmProfile", "Light", "-WslProcessors", "1",
    "-WslNetworking", "mirrored", "-WslGui", "true", "-VhdSizeGB", "32", "-WslInitTimeout", "45000", "-WslAppendWindowsPath", "false")
Test-Run "every option given" $run -Contains @(
    "Virtual machine: Light", "Processors: 1 from -WslProcessors", "[wsl2] processors: - -> 1", "Networking: mirrored",
    "[wsl2] networkingMode: - -> mirrored", "[wsl2] dnsTunneling: - -> true", "[wsl2] autoProxy: - -> true",
    "[wsl2] firewall: - -> true", "[wsl2] guiApplications: - -> true", "Disk limit: 32 GB", "[wsl2] defaultVhdSize: - -> 32GB",
    "wsl --install -d Ubuntu-26.04 --vhd-size 32GB",
    "--shell fish --wsl-init-timeout 45000 --wsl-append-windows-path false"
)

# --- A .wslconfig already there, unattended: without options it is kept as it is.
$mine = "# my settings`r`n[wsl2]`r`nmemory=3GB`r`nkernelCommandLine = vsyscall=emulate`r`n"
$run = Invoke-DryRun -Options @("-Distro", "Debian") -WslConfig $mine
Test-Run "an existing .wslconfig and no WSL option: kept as it is" $run -Contains @(
    "exists and no WSL option was given: kept as it is"
) -Lacks @("Virtual machine:", "Networking:", "[wsl2] ")

# ... with options, only what they name changes, and they win over the values in the file.
$run = Invoke-DryRun -Options @("-Distro", "Debian", "-WslMemoryGB", "4", "-WslNetworking", "mirrored") -WslConfig $mine
Test-Run "an existing .wslconfig and options: only those change" $run -Contains @(
    "exists. These settings change", "[wsl2] memory: 3GB -> 4GB", "[wsl2] networkingMode: - -> mirrored",
    "[wsl2] dnsTunneling: - -> true"
) -Lacks @("swap:", "processors:", "sparseVhd", "guiApplications", "maxCrashDumpCount")

# ... and a profile given as an option replaces the RAM, processors and swap of the file.
$run = Invoke-DryRun -Options @("-Distro", "Debian", "-VmProfile", "Light") -WslConfig $mine
Test-Run "an existing .wslconfig and -VmProfile Light" $run -Contains @(
    "Virtual machine: Light", "[wsl2] memory: 3GB -> ", "[wsl2] processors: - -> ", "[wsl2] swap: - -> "
) -Lacks @("networkingMode", "sparseVhd")

# ... an option equal to the file: nothing to change.
$run = Invoke-DryRun -Options @("-Distro", "Debian", "-WslMemoryGB", "3") -WslConfig $mine
Test-Run "an existing .wslconfig that already has the option" $run -Contains @("already has these settings") -Lacks @("[wsl2] ")

# --- Invalid options: refused before anything changes, each problem named.
$invalid = @(
    @(@("-Distro", "Fedora"), "-Distro: Debian, Ubuntu-24.04, Ubuntu-26.04"),
    @(@("-Shell", "tcsh"), "-Shell: gash, bash-plus, zsh, fish, bash"),
    @(@("-VmProfile", "Huge"), "-VmProfile: Light, Balanced, Performance, Current"),
    @(@("-WslMemoryGB", "1"), "-WslMemoryGB: from 2 to "),
    @(@("-WslMemoryGB", "4096"), "-WslMemoryGB: from 2 to "),
    @(@("-WslProcessors", "4096"), "-WslProcessors: from 1 to "),
    @(@("-WslSwapGB", "65"), "-WslSwapGB: from 0 to 64"),
    @(@("-WslNetworking", "bridged"), "-WslNetworking: nat, mirrored"),
    @(@("-WslGui", "maybe"), "-WslGui: true, false"),
    @(@("-VhdSizeGB", "5"), "-VhdSizeGB: 0 (no limit) or from 16 to "),
    @(@("-VhdSizeGB", "99999999"), "-VhdSizeGB: 0 (no limit) or from 16 to "),
    @(@("-WslInitTimeout", "5"), "-WslInitTimeout: from 1000 to 600000"),
    @(@("-WslAppendWindowsPath", "yes"), "-WslAppendWindowsPath: true, false"),
    @(@("-StackScript", "C:\no\such\file.sh"), "-StackScript: C:\no\such\file.sh")
)
foreach ($case in $invalid) {
    $run = Invoke-DryRun -Options $case[0]
    Test-Run "refused: $($case[0] -join ' ')" $run -Status 1 -Contains @($case[1], "invalid options, nothing was changed") -Lacks @("[2/8]")
}
$run = Invoke-DryRun -Options @("-Shell", "tcsh", "-WslGui", "maybe", "-WslSwapGB", "99") -WslConfig $mine
Test-Run "several invalid options: all of them are listed, .wslconfig stays" $run -Status 1 -Contains @(
    "-Shell: ", "-WslGui: ", "-WslSwapGB: "
)

Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "1..$($script:count)"
if ($script:failed -gt 0) {
    Write-Host "# $($script:failed) of $($script:count) checks failed"
    exit 1
}
Write-Host "# all $($script:count) checks passed"
exit 0
