# Runs the Windows setup end to end on a real WSL2, the way the README describes it, and checks the result.
#
#   pwsh tests/wsl/run.ps1 -Distro Debian [-Shell S] [-VmProfile P] [-WslNetworking N] [-VhdSizeGB N]
#                          [-WslInitTimeout MS] [-WslAppendWindowsPath true|false] [-PresetWslConfig] [-LogDir <dir>]
#
#   1. wsl --install -d <Distro> --no-launch, then a user "dev" with passwordless sudo: this stands in for
#      the user name and password that you type when the distribution starts for the first time.
#      With -PresetWslConfig a .wslconfig of your own is already there.
#   2. install/win11.ps1 -Unattended -StackScript install/lamp-lapp-stack.sh and the options above, in Windows
#      PowerShell 5.1 (the PowerShell that every Windows has); it ends with "wsl --terminate", a restart of the
#      distro. Then .wslconfig must hold what the options and the profile say, and nothing else may have changed
#   3. the Desktop shortcuts it created
#   4. tests/verify-stack.sh install (runs the guide's "first local site"; checks that the virtual machine got
#      the RAM, processors, swap, network mode and disk limit of .wslconfig)
#   5. Windows reaches the site: the lines of "gash hte hosts windows" go in the Windows hosts file,
#      then curl.exe on Windows opens https://shop.test/
#   6. wsl --terminate, then tests/verify-stack.sh reboot
#   7. win11.ps1 again: completed steps are skipped, .wslconfig and the stack stay as they are
#
# Meant for a disposable Windows machine such as a CI runner: it installs a distribution, writes
# %UserProfile%\.wslconfig, edits the Windows hosts file and creates Desktop shortcuts.
#
# Author: Maurizio Fonte (https://www.mauriziofonte.it)
# License: MIT License

param (
    [Parameter(Mandatory = $true)] [ValidateSet("Debian", "Ubuntu-24.04", "Ubuntu-26.04")] [String]$Distro,
    [ValidateSet("gash", "bash-plus", "zsh", "fish", "bash")] [String]$Shell = "",
    [ValidateSet("Light", "Balanced", "Performance")] [String]$VmProfile = "",
    [ValidateSet("nat", "mirrored")] [String]$WslNetworking = "",
    [Int]$VhdSizeGB = 0,
    [Int]$WslInitTimeout = 0,
    [ValidateSet("true", "false")] [String]$WslAppendWindowsPath = "",
    [Switch]$PresetWslConfig,
    [String]$LogDir = (Join-Path ([System.IO.Path]::GetTempPath()) "wsl-setup-test")
)

$ErrorActionPreference = "Stop"
$env:WSL_UTF8 = "1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
. (Join-Path $repo "tests/powershell/Import-Win11Function.ps1")
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$setupOptions = @("-Distro", $Distro)
if ($Shell) { $setupOptions += @("-Shell", $Shell) }
if ($VmProfile) { $setupOptions += @("-VmProfile", $VmProfile) }
if ($WslNetworking) { $setupOptions += @("-WslNetworking", $WslNetworking) }
if ($VhdSizeGB -gt 0) { $setupOptions += @("-VhdSizeGB", $VhdSizeGB) }
if ($WslInitTimeout -gt 0) { $setupOptions += @("-WslInitTimeout", $WslInitTimeout) }
if ($WslAppendWindowsPath) { $setupOptions += @("-WslAppendWindowsPath", $WslAppendWindowsPath) }

function Write-Step {
    param ([String]$Text)
    Write-Host ""
    Write-Host "== $Text" -ForegroundColor Cyan
}

function Invoke-Native {
    # Runs a native command, echoes its output, and stops on a non-zero exit status.
    param ([String]$What, [ScriptBlock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit status $LASTEXITCODE" }
}

function Invoke-Setup {
    param ([String]$Log)
    $setup = Join-Path $repo "install/win11.ps1"
    $stack = Join-Path $repo "install/lamp-lapp-stack.sh"
    Write-Host "win11.ps1 $($setupOptions -join ' ') -Unattended"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setup @setupOptions -Unattended -StackScript $stack 2>&1 |
        Tee-Object -FilePath $Log
    if ($LASTEXITCODE -ne 0) { throw "win11.ps1 failed with exit status $LASTEXITCODE (log: $Log)" }
}

function Invoke-Verify {
    param ([String]$Phase)
    $script = ((wsl.exe -d $Distro --exec wslpath -u (Join-Path $repo "tests/verify-stack.sh")) -join "").Trim()
    wsl.exe -d $Distro -u dev --cd "~" --exec env @expect bash $script $Phase 2>&1 | Tee-Object -FilePath (Join-Path $LogDir "verify-$Phase.log")
    if ($LASTEXITCODE -ne 0) { throw "verify-stack.sh $Phase failed" }
}

Write-Step "WSL"
Invoke-Native "wsl --version" { wsl.exe --version }
$help = (wsl.exe --help) -join "`n"
foreach ($option in @("--vhd-size", "--resize")) {
    if (-not $help.Contains($option)) { throw "wsl --help does not list $option, which win11.ps1 uses for the disk limit" }
    Write-Host "ok - wsl --help lists $option"
}

Write-Step "1. Install $Distro and its user (stands in for the first start, where you choose them)"
Invoke-Native "wsl --install" { wsl.exe --install -d $Distro --no-launch --web-download }
Invoke-Native "create the user" {
    wsl.exe -d $Distro -u root --exec bash -c "id -u dev >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo dev; echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev; chmod 0440 /etc/sudoers.d/dev"
}
wsl.exe --manage $Distro --set-default-user dev
if ($LASTEXITCODE -ne 0) {
    # Older WSL: the same through /etc/wsl.conf.
    Invoke-Native "default user" { wsl.exe -d $Distro -u root --exec bash -c "printf '\n[user]\ndefault=dev\n' >>/etc/wsl.conf" }
}
Invoke-Native "wsl --terminate" { wsl.exe --terminate $Distro }
$who = ((wsl.exe -d $Distro --exec whoami) -join "").Trim()
if ($who -ne "dev") { throw "default user is '$who', expected 'dev'" }

# A .wslconfig of your own: unattended, only what the options name may change in it.
$preset = "# kept by the setup`r`n[wsl2]`r`nnestedVirtualization=true`r`nmemory=3GB`r`n"
if ($PresetWslConfig) { [IO.File]::WriteAllText($wslConfigPath, $preset) }
elseif (Test-Path -LiteralPath $wslConfigPath) { Remove-Item -LiteralPath $wslConfigPath }

Write-Step "2. win11.ps1 -Unattended (Windows PowerShell 5.1)"
Invoke-Setup -Log (Join-Path $LogDir "setup-1.log")

# What .wslconfig must hold: the profile (Balanced unless given; none with a .wslconfig of your own and no
# -VmProfile), the network mode (NAT unless given), no WSLg and the base set, but on a .wslconfig of your
# own only the keys the options name.
$hostInfo = Get-HostResources
$chosen = if ($VmProfile) { $VmProfile } elseif (-not $PresetWslConfig) { "Balanced" } else { "" }
$expectedProfile = Get-VmProfiles -InstalledGB $hostInfo.InstalledGB -UsableGB $hostInfo.UsableGB -Threads $hostInfo.Threads |
    Where-Object { $_.Name -eq $chosen }
$networking = if ($WslNetworking) { $WslNetworking } elseif (-not $PresetWslConfig) { "nat" } else { "" }
$gui = if ($PresetWslConfig) { $null } else { $false }
$want = @(Get-WslSettings -MemoryGB $expectedProfile.MemoryGB -Processors $expectedProfile.Processors -SwapGB $expectedProfile.SwapGB `
        -Networking $networking -Gui $gui -Base (-not $PresetWslConfig) -VhdSizeGB $VhdSizeGB)
$written = [IO.File]::ReadAllText($wslConfigPath)
Write-Host "--- $wslConfigPath"
Write-Host $written
$missing = @(Get-IniChange -Text $written -Settings $want)
if ($missing) { throw ".wslconfig lacks: $($missing -join '; ')" }
$extra = @((Read-IniValues -Text $written).Keys | Where-Object {
        $key = $_
        -not ($want | Where-Object { "$($_.Section).$($_.Key)".ToLower() -eq $key })
    })
$allowed = if ($PresetWslConfig) { @("wsl2.nestedvirtualization") + @(if (-not $expectedProfile) { "wsl2.memory" }) } else { @() }
$extra = @($extra | Where-Object { $allowed -notcontains $_ })
if ($extra) { throw ".wslconfig has keys nobody asked for: $($extra -join ', ')" }
Write-Host "ok - .wslconfig holds the settings of the options and the profile, and nothing else"
if ($PresetWslConfig) {
    if (-not $written.StartsWith("# kept by the setup`r`n[wsl2]`r`nnestedVirtualization=true`r`n")) { throw "your own lines of .wslconfig were not kept" }
    $backups = @(Get-ChildItem -Path "$wslConfigPath.bak-*")
    if ($backups.Count -ne 1 -or [IO.File]::ReadAllText($backups[0].FullName) -cne $preset) { throw "no backup copy of your .wslconfig" }
    Write-Host "ok - your own lines are kept, and $($backups[0].Name) holds the file as it was"
}

# What verify-stack.sh checks inside the virtual machine.
$expect = @("SHELL_CHOICE=$(if ($Shell) { $Shell } else { 'gash' })")
if ($WslInitTimeout -gt 0) { $expect += "WSL_INIT_TIMEOUT=$WslInitTimeout" }
if ($WslAppendWindowsPath) { $expect += "WSL_APPEND_PATH=$WslAppendWindowsPath" }
if ($expectedProfile) { $expect += @("VM_MEMORY_GB=$($expectedProfile.MemoryGB)", "VM_PROCESSORS=$($expectedProfile.Processors)", "VM_SWAP_GB=$($expectedProfile.SwapGB)") }
$expect += "VM_NETWORKING=$(if ($networking) { $networking } else { 'nat' })"
if ($VhdSizeGB -gt 0) { $expect += "VM_DISK_GB=$VhdSizeGB" }
Write-Host "verify-stack.sh expects: $($expect -join ' ')"

Write-Step "3. Desktop shortcuts"
$desktop = [System.Environment]::GetFolderPath("Desktop")
foreach ($name in @("$Distro.lnk", "$Distro Home.lnk")) {
    $path = Join-Path $desktop $name
    if (-not (Test-Path $path)) { throw "missing shortcut: $path" }
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
    Write-Host "ok - $name -> $($link.TargetPath) $($link.Arguments)"
}
$homeLink = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop "$Distro Home.lnk"))
if ($homeLink.TargetPath -ne "\\wsl.localhost\$Distro\home\dev") { throw "home shortcut points to $($homeLink.TargetPath)" }
if (-not (Test-Path -LiteralPath $homeLink.TargetPath)) { throw "Windows cannot open $($homeLink.TargetPath)" }
Write-Host "ok - Windows opens $($homeLink.TargetPath)"

Write-Step "4. Verify the stack"
Invoke-Verify -Phase "install"

Write-Step "5. Windows opens https://shop.test/"
$lines = @(wsl.exe -d $Distro -u dev --exec /home/dev/.gash/bin/gash hte hosts windows | Where-Object { $_ -match "^\s*\d" })
if ($lines.Count -eq 0) { throw "gash hte hosts windows printed no hosts line" }
$hostsFile = Join-Path $env:WINDIR "System32\drivers\etc\hosts"
Add-Content -LiteralPath $hostsFile -Value $lines
Write-Host "added to the Windows hosts file: $($lines -join ' | ')"
$body = (& curl.exe -ks --max-time 30 https://shop.test/) -join "`n"
if ($body -notmatch "^PHP 8\.4\.") { throw "Windows got '$body' from https://shop.test/" }
Write-Host "ok - Windows: https://shop.test/ answers '$body'"

Write-Step "6. Restart the distribution, then verify again"
Invoke-Native "wsl --terminate" { wsl.exe --terminate $Distro }
Invoke-Verify -Phase "reboot"

Write-Step "7. win11.ps1 again: nothing may change"
$second = Join-Path $LogDir "setup-2.log"
Invoke-Setup -Log $second
if ([IO.File]::ReadAllText($wslConfigPath) -cne $written) { throw "the second run changed .wslconfig" }
Write-Host "ok - .wslconfig is as the first run left it"
# The installer reports each change on a line of its own ("  wrote FILE", "  linked ..."), colored.
$changed = Select-String -LiteralPath $second -Pattern '^(\x1b\[[0-9;]*m)?\s{2}(wrote|linked|installed|disabled|removed) '
if ($changed) {
    $changed | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }
    throw "the second run changed the lines above"
}
if (-not (Select-String -LiteralPath $second -Pattern "is already installed: it is kept as it is|\u00e8 gi\u00e0 installata")) {
    throw "the second run did not report the distribution as already installed"
}
Write-Host "ok - the second run changed nothing"

Write-Host ""
Write-Host "Passed: $Distro" -ForegroundColor Green
