# Bootstrap for win11.ps1, meant to be run straight from the web:
#
#   irm https://wsl.mauriziofonte.it | iex
#   & ([scriptblock]::Create((irm https://wsl.mauriziofonte.it))) -Distro Ubuntu-26.04
#
# wsl.mauriziofonte.it redirects every path to the latest GitHub release of the repository.
# It saves win11.ps1 to %LOCALAPPDATA%\WSL2Setup (the setup resumes from that file after the reboot)
# and starts it elevated: the user only confirms the UAC prompt.
# Keep this file ASCII-only and without a BOM: it is evaluated as a string by Invoke-Expression.
#
# Author: Maurizio Fonte (https://www.mauriziofonte.it)
# License: MIT License

# No validation attributes here: under "irm | iex" this block runs as plain variable declarations
# in the caller's scope, and a ValidateSet would reject the empty default. win11.ps1 validates -Distro and -Shell.
param (
    [String]$Distro = "",
    [String]$Shell = "",
    [Switch]$Unattended,
    [Switch]$DryRun,
    [Switch]$SkipWindowsVersionCheck,
    [Switch]$Force
)

$source = "https://wsl.mauriziofonte.it/win11.ps1"
$folder = Join-Path $env:LOCALAPPDATA "WSL2Setup"
$target = Join-Path $folder "win11.ps1"

# Italian when the Windows display language is Italian (ASCII-only wording, see above).
if ((Get-UICulture).TwoLetterISOLanguageName -eq "it") {
    $textDownload = "Download dell'installazione WSL2..."
    $textDownloadKo = "Download non riuscito"
    $textStart = "Si apre una nuova finestra: conferma la richiesta di amministratore (UAC) per continuare."
    $textCancelled = "Richiesta di amministratore annullata: per riprovare, esegui di nuovo il comando."
}
else {
    $textDownload = "Downloading the WSL2 setup..."
    $textDownloadKo = "Download failed"
    $textStart = "A new window opens: confirm the administrator (UAC) prompt to continue."
    $textCancelled = "Administrator prompt cancelled: run the command again to retry."
}

Write-Host $textDownload -ForegroundColor Cyan
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # -ErrorAction per cmdlet, not $ErrorActionPreference: under "irm | iex" this runs in the caller's session scope.
    New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Invoke-WebRequest -Uri $source -OutFile $target -UseBasicParsing -ErrorAction Stop
    if (-not (Test-Path $target) -or (Get-Item $target).Length -eq 0) {
        throw "Empty download: $source"
    }
}
catch {
    Write-Host "$textDownloadKo ($source): $($_.Exception.Message)" -ForegroundColor White -BackgroundColor Red
    return
}

$arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$target`"")
if ($Distro) { $arguments += @("-Distro", $Distro) }
if ($Shell) { $arguments += @("-Shell", $Shell) }
if ($Unattended) { $arguments += "-Unattended" }
if ($DryRun) { $arguments += "-DryRun" }
if ($SkipWindowsVersionCheck) { $arguments += "-SkipWindowsVersionCheck" }
if ($Force) { $arguments += "-Force" }

Write-Host $textStart -ForegroundColor Cyan
try {
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs -ErrorAction Stop
}
catch {
    Write-Host $textCancelled -ForegroundColor Yellow
}
