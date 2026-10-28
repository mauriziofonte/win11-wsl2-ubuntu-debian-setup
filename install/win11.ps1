# WSL2 + Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 setup for Windows 11 (and Windows 10 1903+ with -SkipWindowsVersionCheck)
#
# Author: Maurizio Fonte (https://www.mauriziofonte.it)
# Version: 2.1.0
# Release Date: 2023-09-04
# Last Update: 2026-10-28
# License: MIT License
#
# Usually started by the bootstrap: irm https://wsl.mauriziofonte.it | iex
# Direct use: .\win11.ps1 [-Distro Debian|Ubuntu-24.04|Ubuntu-26.04] [-Shell gash|zsh|bash] [-Unattended]
#                         [-StackScript <path>] [-DryRun] [-SkipWindowsVersionCheck] [-Force]
#
# Flow: checks -> WSL (reboot only when Windows needs it, then resume by itself) -> WSL update -> distribution
# -> LAMP/LAPP stack -> Docker Desktop (optional) -> Desktop shortcuts -> summary.
# Running it again is safe: completed steps are detected and skipped.
#
# Report issues: https://github.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup/issues

# -Distro and -Shell are validated below, not with [ValidateSet]: the attribute would stay on the variable
# and reject the empty value read back from the registry.
# -Unattended answers every question with its default and never waits for Enter; creating the Linux user of a
# new distribution still needs you. -StackScript runs a local copy of lamp-lapp-stack.sh instead of the
# released one (a copy you reviewed, or the one under test in CI).
param (
    [String]$Distro = "",
    [String]$Shell = "",
    [Switch]$Unattended,
    [String]$StackScript = "",
    [Switch]$DryRun,
    [Switch]$SkipWindowsVersionCheck,
    [Switch]$Force
)

$scriptVersion = "2.1.0"
$installHost = "https://wsl.mauriziofonte.it"
$repoRawBase = "https://raw.githubusercontent.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup/main"
$registryPath = "HKCU:\Software\WSL2Setup"
$runOncePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
$workDir = Join-Path $env:LOCALAPPDATA "WSL2Setup"
$totalSteps = 7
$supportedDistros = @("Debian", "Ubuntu-24.04", "Ubuntu-26.04")
$supportedShells = @("gash", "zsh", "bash")

# wsl.exe writes UTF-16 to a pipe unless told otherwise: PowerShell 5.1 would read it with NUL bytes between letters.
# With WSL_UTF8 it writes UTF-8, so the console must decode native output (and print ours) as UTF-8 too.
$env:WSL_UTF8 = "1"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Italian when the Windows display language is Italian, English otherwise.
$language = if ((Get-UICulture).TwoLetterISOLanguageName -eq "it") { "it" } else { "en" }

$messages = @{
    "en" = @{
        "title" = "WSL2 + LAMP/LAPP development environment"
        "subtitle" = "Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 on Windows"
        "dry_run" = "DRY RUN: nothing will be changed on this computer."
        "log_file" = "Log: {0}"
        "elevating" = "Administrator rights are needed: confirm the UAC prompt."
        "press_enter_exit" = "Press Enter to close this window."
        "press_enter_continue" = "Press Enter to continue."
        "yes_no_invalid" = "Please answer y (yes) or n (no)."
        "auto_yes" = "yes (unattended)"
        "auto_no" = "no (unattended)"
        "step_checks" = "Checking this computer"
        "step_wsl" = "Windows Subsystem for Linux"
        "step_update" = "Updating WSL"
        "step_distro" = "Linux distribution"
        "step_stack" = "LAMP/LAPP stack"
        "step_docker" = "Docker Desktop"
        "step_shortcuts" = "Desktop shortcuts"
        "admin_ok" = "Running as Administrator"
        "internet_ok" = "Internet connection OK"
        "internet_ko" = "https://github.com is not reachable. Check the connection, then press Enter to retry."
        "windows_ok" = "Windows build {0}"
        "windows_ko" = "This needs Windows 11 (build 22000 or later). On Windows 10 1903+ run it with -SkipWindowsVersionCheck."
        "ask_distro" = "Which Linux distribution do you want to install?"
        "distro_1" = "Debian 13        (recommended)"
        "distro_2" = "Ubuntu 24.04 LTS"
        "distro_3" = "Ubuntu 26.04 LTS"
        "ask_distro_choice" = "Your choice [1-3, Enter = 1]"
        "distro_chosen" = "Distribution: {0}"
        "wsl_present" = "WSL is already installed ({0})"
        "wsl_installing" = "Installing WSL and the Virtual Machine Platform..."
        "wsl_install_failed" = "WSL could not be installed (exit code {0}). Run 'wsl --install --no-distribution' in this window to see the error."
        "wsl_installed" = "WSL installed"
        "reboot_needed" = "Windows must restart to finish enabling WSL. The setup continues by itself after you log in again."
        "reboot_ask" = "Save your work, then press Enter to restart now."
        "reboot_later" = "Restart Windows when you are ready: the setup continues by itself at your next login."
        "resumed" = "Resuming the setup after the restart."
        "wsl_version" = "WSL {0}"
        "wsl_version_ko" = "WSL {0} is too old (2.0 or later is required): run 'wsl --update', then run this setup again."
        "wsl_version_unknown" = "Cannot read the WSL version ('wsl --version' failed)."
        "distro_present" = "{0} is already installed: it is kept as it is"
        "distro_not_online" = "{0} is not in the list of installable distributions ('wsl --list --online')."
        "distro_installing" = "Installing {0}. When asked, choose your Linux user name and password (the password is the one sudo asks for)."
        "distro_exit_hint" = "When you see the Linux prompt, type  exit  and press Enter to come back here."
        "distro_install_failed" = "{0} could not be installed (exit code {1})."
        "distro_user_ko" = "{0} has no regular user yet. Open it once from the Start menu, create the user, then run this setup again."
        "distro_user" = "Linux user: {0}"
        "ask_default" = "Make {0} the default WSL distribution? (now: {1})"
        "default_set" = "{0} is the default WSL distribution"
        "ask_stack" = "Install the LAMP/LAPP stack (PHP 5.6-8.5, Apache, MariaDB, PostgreSQL, Redis, Gash) in {0}?"
        "stack_info" = "This takes a while and prints a lot of output. Linux asks once for your sudo password."
        "stack_download_ko" = "Cannot download the stack installer: {0}"
        "stack_local" = "Stack installer: local copy {0}"
        "stack_ok" = "LAMP/LAPP stack installed"
        "stack_ko" = "The stack installer stopped with an error (exit code {0}). Its log is in ~/.local/state/lamp-lapp-stack/ inside {1}. Fix the cause and run this setup again: completed steps are skipped."
        "stack_skipped" = "Skipped"
        "distro_restart" = "Restarting {0} to apply its new WSL settings"
        "ask_docker" = "Install Docker Desktop for Windows (it uses this same WSL)?"
        "docker_present" = "Docker Desktop is already installed"
        "docker_installing" = "Downloading and installing Docker Desktop (a few minutes)..."
        "docker_ok" = "Docker Desktop installed: sign out and back in at the end to complete its setup"
        "docker_ko" = "Docker Desktop could not be installed (exit code {0})"
        "shortcuts_ok" = "Created on the Desktop: '{0}' (terminal) and '{1}' (home folder)"
        "done_title" = "Setup completed"
        "done_open" = "Open a Linux terminal with the '{0}' shortcut, or run:  wsl -d {0}"
        "done_site" = "First local site:  gash hte site create --domain shop.test --docroot public"
        "done_hosts" = "Names for the Windows browser:  gash hte hosts windows  (add its lines to the Windows hosts file)"
        "done_guide" = "Guide: https://github.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup"
        "failed" = "The setup stopped: {0}"
    }
    "it" = @{
        "title" = "Ambiente di sviluppo WSL2 + LAMP/LAPP"
        "subtitle" = "Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 su Windows"
        "dry_run" = "PROVA (DRY RUN): nessuna modifica verrà fatta su questo computer."
        "log_file" = "Log: {0}"
        "elevating" = "Servono i diritti di amministratore: conferma la richiesta UAC."
        "press_enter_exit" = "Premi Invio per chiudere questa finestra."
        "press_enter_continue" = "Premi Invio per continuare."
        "yes_no_invalid" = "Rispondi s (sì) oppure n (no)."
        "auto_yes" = "sì (automatico)"
        "auto_no" = "no (automatico)"
        "step_checks" = "Controllo del computer"
        "step_wsl" = "Sottosistema Windows per Linux"
        "step_update" = "Aggiornamento di WSL"
        "step_distro" = "Distribuzione Linux"
        "step_stack" = "Stack LAMP/LAPP"
        "step_docker" = "Docker Desktop"
        "step_shortcuts" = "Collegamenti sul Desktop"
        "admin_ok" = "In esecuzione come amministratore"
        "internet_ok" = "Connessione Internet funzionante"
        "internet_ko" = "https://github.com non è raggiungibile. Controlla la connessione, poi premi Invio per riprovare."
        "windows_ok" = "Windows build {0}"
        "windows_ko" = "Serve Windows 11 (build 22000 o successiva). Su Windows 10 1903 o successivo eseguilo con -SkipWindowsVersionCheck."
        "ask_distro" = "Quale distribuzione Linux vuoi installare?"
        "distro_1" = "Debian 13        (consigliata)"
        "distro_2" = "Ubuntu 24.04 LTS"
        "distro_3" = "Ubuntu 26.04 LTS"
        "ask_distro_choice" = "La tua scelta [1-3, Invio = 1]"
        "distro_chosen" = "Distribuzione: {0}"
        "wsl_present" = "WSL è già installato ({0})"
        "wsl_installing" = "Installazione di WSL e della Piattaforma macchina virtuale..."
        "wsl_install_failed" = "Impossibile installare WSL (codice di uscita {0}). Esegui 'wsl --install --no-distribution' in questa finestra per vedere l'errore."
        "wsl_installed" = "WSL installato"
        "reboot_needed" = "Windows deve riavviarsi per completare l'attivazione di WSL. L'installazione riprende da sola dopo che avrai effettuato di nuovo l'accesso."
        "reboot_ask" = "Salva il tuo lavoro, poi premi Invio per riavviare adesso."
        "reboot_later" = "Riavvia Windows quando sei pronto: l'installazione riprende da sola al prossimo accesso."
        "resumed" = "L'installazione riprende dopo il riavvio."
        "wsl_version" = "WSL {0}"
        "wsl_version_ko" = "WSL {0} è troppo vecchio (serve la 2.0 o successiva): esegui 'wsl --update', poi esegui di nuovo questa installazione."
        "wsl_version_unknown" = "Impossibile leggere la versione di WSL ('wsl --version' non ha funzionato)."
        "distro_present" = "{0} è già installata: viene mantenuta così com'è"
        "distro_not_online" = "{0} non è tra le distribuzioni installabili ('wsl --list --online')."
        "distro_installing" = "Installazione di {0}. Quando richiesto, scegli nome utente e password di Linux (la password è quella che chiede sudo)."
        "distro_exit_hint" = "Quando vedi il prompt di Linux, digita  exit  e premi Invio per tornare qui."
        "distro_install_failed" = "Impossibile installare {0} (codice di uscita {1})."
        "distro_user_ko" = "{0} non ha ancora un utente normale. Aprila una volta dal menu Start, crea l'utente, poi esegui di nuovo questa installazione."
        "distro_user" = "Utente Linux: {0}"
        "ask_default" = "Rendere {0} la distribuzione WSL predefinita? (ora: {1})"
        "default_set" = "{0} è la distribuzione WSL predefinita"
        "ask_stack" = "Installare lo stack LAMP/LAPP (PHP 5.6-8.5, Apache, MariaDB, PostgreSQL, Redis, Gash) in {0}?"
        "stack_info" = "Richiede un po' di tempo e produce molto output. Linux chiede una sola volta la password di sudo."
        "stack_download_ko" = "Impossibile scaricare l'installer dello stack: {0}"
        "stack_local" = "Installer dello stack: copia locale {0}"
        "stack_ok" = "Stack LAMP/LAPP installato"
        "stack_ko" = "L'installer dello stack si è fermato con un errore (codice di uscita {0}). Il log è in ~/.local/state/lamp-lapp-stack/ dentro {1}. Risolvi la causa ed esegui di nuovo questa installazione: i passi già completati vengono saltati."
        "stack_skipped" = "Saltato"
        "distro_restart" = "Riavvio di {0} per applicare le nuove impostazioni di WSL"
        "ask_docker" = "Installare Docker Desktop per Windows (usa questo stesso WSL)?"
        "docker_present" = "Docker Desktop è già installato"
        "docker_installing" = "Download e installazione di Docker Desktop (qualche minuto)..."
        "docker_ok" = "Docker Desktop installato: alla fine esci dalla sessione e rientra per completarne la configurazione"
        "docker_ko" = "Impossibile installare Docker Desktop (codice di uscita {0})"
        "shortcuts_ok" = "Creati sul Desktop: '{0}' (terminale) e '{1}' (cartella home)"
        "done_title" = "Installazione completata"
        "done_open" = "Apri un terminale Linux con il collegamento '{0}', oppure esegui:  wsl -d {0}"
        "done_site" = "Primo sito locale:  gash hte site create --domain shop.test --docroot public"
        "done_hosts" = "Nomi per il browser di Windows:  gash hte hosts windows  (aggiungi le righe al file hosts di Windows)"
        "done_guide" = "Guida: https://github.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup"
        "failed" = "L'installazione si è fermata: {0}"
    }
}

function Msg {
    param ([Parameter(Mandatory = $true)] [String]$Key, [Object[]]$Format = @())
    $text = $messages[$language][$Key]
    if ($Format.Count -gt 0) { $text = $text -f $Format }
    return $text
}

function Write-Banner {
    $line = "=" * 64
    Write-Host ""
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host "   $(Msg 'title')" -ForegroundColor White
    Write-Host "   $(Msg 'subtitle')  -  v$scriptVersion" -ForegroundColor Gray
    Write-Host "  $line" -ForegroundColor DarkCyan
    if ($DryRun) { Write-Host "   $(Msg 'dry_run')" -ForegroundColor Yellow }
    Write-Host ""
}

function Write-Step {
    param ([Int]$Number, [String]$Key)
    Write-Host ""
    Write-Host "  [$Number/$totalSteps] " -ForegroundColor DarkCyan -NoNewline
    Write-Host (Msg $Key) -ForegroundColor White
}

function Write-Ok { param ([String]$Text) Write-Host "        [ OK ] " -ForegroundColor Green -NoNewline; Write-Host $Text }
function Write-Info { param ([String]$Text) Write-Host "        [ .. ] " -ForegroundColor Cyan -NoNewline; Write-Host $Text }
function Write-Warn { param ([String]$Text) Write-Host "        [WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $Text -ForegroundColor Yellow }

function Stop-Setup {
    param ([Parameter(Mandatory = $true)] [String]$Text)
    Write-Host ""
    Write-Host "        [FAIL] " -ForegroundColor Red -NoNewline
    Write-Host (Msg "failed" @($Text)) -ForegroundColor Red
    if (-not $Unattended) {
        Write-Host ""
        Write-Host "  $(Msg 'press_enter_exit')" -ForegroundColor Gray
        Read-Host | Out-Null
    }
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

function Read-YesNo {
    param ([Parameter(Mandatory = $true)] [String]$Question, [Bool]$Default = $true)
    $hint = if ($language -eq "it") { if ($Default) { "(S/n)" } else { "(s/N)" } } else { if ($Default) { "(Y/n)" } else { "(y/N)" } }
    if ($Unattended) {
        Write-Host "        [ ?? ] " -ForegroundColor Magenta -NoNewline
        Write-Host "$Question $hint $(if ($Default) { Msg 'auto_yes' } else { Msg 'auto_no' })"
        return $Default
    }
    while ($true) {
        Write-Host "        [ ?? ] " -ForegroundColor Magenta -NoNewline
        Write-Host "$Question $hint " -NoNewline
        $answer = (Read-Host).Trim().ToLower()
        if ($answer -eq "") { return $Default }
        if ($answer -in @("y", "yes", "s", "si", "sì")) { return $true }
        if ($answer -in @("n", "no")) { return $false }
        Write-Warn (Msg "yes_no_invalid")
    }
}

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Command line that runs this script again with the same options (used for elevation and for the resume after reboot).
function Get-SelfArguments {
    param ([String]$ChosenDistro)
    $list = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    if ($ChosenDistro) { $list += @("-Distro", $ChosenDistro) }
    if ($Shell) { $list += @("-Shell", $Shell) }
    if ($Unattended) { $list += "-Unattended" }
    if ($StackScript) { $list += @("-StackScript", "`"$StackScript`"") }
    if ($DryRun) { $list += "-DryRun" }
    if ($SkipWindowsVersionCheck) { $list += "-SkipWindowsVersionCheck" }
    return $list
}

function Get-SetupValue {
    param ([Parameter(Mandatory = $true)] [String]$Key)
    return (Get-ItemProperty -Path $registryPath -Name $Key -ErrorAction SilentlyContinue).$Key
}

function Set-SetupValue {
    param ([Parameter(Mandatory = $true)] [String]$Key, [Parameter(Mandatory = $true)] $Value)
    if (-not (Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }
    Set-ItemProperty -Path $registryPath -Name $Key -Value $Value
}

function Get-InstalledDistros {
    return @(wsl.exe --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
}

function Get-DefaultDistro {
    # "wsl --list --verbose" marks the default distribution with "*"; the marker is not localized.
    foreach ($line in (wsl.exe --list --verbose 2>$null)) {
        $clean = ($line -replace "`0", "").Trim()
        if ($clean.StartsWith("*")) { return ($clean.TrimStart("*").Trim() -split "\s+")[0] }
    }
    return ""
}

function Test-OnlineDistro {
    param ([Parameter(Mandatory = $true)] [String]$Name)
    foreach ($line in (wsl.exe --list --online 2>$null)) {
        if ((($line -replace "`0", "").Trim() -split "\s+")[0] -eq $Name) { return $true }
    }
    return $false
}

function Get-WslVersion {
    # "wsl --version" fails on the inbox stub of old Windows builds; its first line holds the WSL version (localized label).
    $output = wsl.exe --version 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $first = ($output | Select-Object -First 1) -replace "`0", ""
    if ($first -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    return $null
}

function Invoke-Download {
    param ([Parameter(Mandatory = $true)] [String]$Url, [Parameter(Mandatory = $true)] [String]$Output)
    Invoke-WebRequest -Uri $Url -OutFile $Output -UseBasicParsing -ErrorAction Stop
    if (-not (Test-Path $Output) -or (Get-Item $Output).Length -eq 0) { throw "Empty download: $Url" }
}

function New-DesktopShortcut {
    param ([String]$Name, [String]$TargetPath, [String]$Arguments, [String]$IconLocation)
    $desktop = [System.Environment]::GetFolderPath('Desktop')
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktop\$Name.lnk")
    $shortcut.TargetPath = $TargetPath
    if ($Arguments) { $shortcut.Arguments = $Arguments }
    if ($IconLocation) { $shortcut.IconLocation = $IconLocation }
    $shortcut.Description = $Name
    $shortcut.Save()
}

# ---------------------------------------------------------------------------------------------
# Elevation: re-launch elevated with the same options (the bootstrap already starts us elevated).
if (-not (Test-Admin)) {
    Write-Host (Msg "elevating") -ForegroundColor Cyan
    Start-Process -FilePath "powershell.exe" -ArgumentList (Get-SelfArguments -ChosenDistro $Distro) -Verb RunAs
    exit 0
}

$Host.UI.RawUI.WindowTitle = Msg "title"
New-Item -Path $workDir -ItemType Directory -Force | Out-Null
$logFile = Join-Path $workDir ("setup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
Start-Transcript -Path $logFile -Append | Out-Null

if ($Force) {
    Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
}
$resumed = ((Get-SetupValue -Key "Phase") -eq "reboot")

Write-Banner
Write-Host "  $(Msg 'log_file' @($logFile))" -ForegroundColor DarkGray
if ($resumed) { Write-Host "  $(Msg 'resumed')" -ForegroundColor Cyan }

# ---------------------------------------------------------------------------------------------
Write-Step 1 "step_checks"
Write-Ok (Msg "admin_ok")

while ($true) {
    try {
        Invoke-WebRequest -Uri "https://github.com" -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop | Out-Null
        break
    }
    catch {
        if ($Unattended) { Stop-Setup "https://github.com: $($_.Exception.Message)" }
        Write-Warn (Msg "internet_ko")
        Read-Host | Out-Null
    }
}
Write-Ok (Msg "internet_ok")

$build = [System.Environment]::OSVersion.Version.Build
if (-not $SkipWindowsVersionCheck -and $build -lt 22000) { Stop-Setup (Msg "windows_ko") }
Write-Ok (Msg "windows_ok" @($build))

# The distribution chosen on the first run is kept in the registry for the resume after reboot.
if ($Distro -and $supportedDistros -notcontains $Distro) { Stop-Setup "-Distro: $($supportedDistros -join ', ')" }
if ($Shell -and $supportedShells -notcontains $Shell) { Stop-Setup "-Shell: $($supportedShells -join ', ')" }
if ($StackScript -and -not (Test-Path -LiteralPath $StackScript -PathType Leaf)) { Stop-Setup "-StackScript: $StackScript" }
if ($StackScript) { $StackScript = (Resolve-Path -LiteralPath $StackScript).Path }
if (-not $Distro) { $Distro = [String](Get-SetupValue -Key "Distro") }
if (-not $Distro -and $Unattended) { $Distro = "Debian" }
if (-not $Distro) {
    Write-Host ""
    Write-Host "        $(Msg 'ask_distro')" -ForegroundColor White
    Write-Host "          1) $(Msg 'distro_1')"
    Write-Host "          2) $(Msg 'distro_2')"
    Write-Host "          3) $(Msg 'distro_3')"
    Write-Host "        $(Msg 'ask_distro_choice'): " -NoNewline
    $Distro = switch ((Read-Host).Trim()) { "2" { "Ubuntu-24.04" } "3" { "Ubuntu-26.04" } default { "Debian" } }
}
Set-SetupValue -Key "Distro" -Value $Distro
Write-Ok (Msg "distro_chosen" @($Distro))

# ---------------------------------------------------------------------------------------------
Write-Step 2 "step_wsl"
$wslVersion = Get-WslVersion
if ($wslVersion) {
    Write-Ok (Msg "wsl_present" @($wslVersion))
}
elseif ($DryRun) {
    Write-Info "wsl --install --no-distribution"
}
else {
    Write-Info (Msg "wsl_installing")
    wsl.exe --install --no-distribution
    if ($LASTEXITCODE -ne 0) { Stop-Setup (Msg "wsl_install_failed" @($LASTEXITCODE)) }
    Write-Ok (Msg "wsl_installed")

    # A restart is needed only while the Virtual Machine Platform is still pending (not yet "Enabled").
    $vmp = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue).State
    if ("$vmp" -ne "Enabled" -or -not (Get-WslVersion)) {
        Write-Warn (Msg "reboot_needed")
        Set-SetupValue -Key "Phase" -Value "reboot"
        # RunOnce: Windows deletes the entry before running it, at the next logon of this user.
        $resume = "powershell.exe " + ((Get-SelfArguments -ChosenDistro $Distro) -join " ")
        Set-ItemProperty -Path $runOncePath -Name "WSL2Setup" -Value $resume
        if ($Unattended) {
            # Never restart a computer nobody is watching: the RunOnce entry resumes at the next login.
            Write-Warn (Msg "reboot_later")
            Stop-Transcript | Out-Null
            exit 3010
        }
        Write-Host ""
        Write-Host "        $(Msg 'reboot_ask')" -ForegroundColor White
        Read-Host | Out-Null
        Stop-Transcript | Out-Null
        Restart-Computer -Force
        exit 0
    }
}
Remove-ItemProperty -Path $runOncePath -Name "WSL2Setup" -ErrorAction SilentlyContinue
Set-SetupValue -Key "Phase" -Value "distro"

# ---------------------------------------------------------------------------------------------
Write-Step 3 "step_update"
if ($DryRun) {
    Write-Info "wsl --update; wsl --set-default-version 2"
    $wslVersion = "2.x"
}
else {
    wsl.exe --update | Out-Null
    wsl.exe --set-default-version 2 | Out-Null
    $wslVersion = Get-WslVersion
    if (-not $wslVersion) { Stop-Setup (Msg "wsl_version_unknown") }
    if ([Version]$wslVersion -lt [Version]"2.0.0") { Stop-Setup (Msg "wsl_version_ko" @($wslVersion)) }
    Write-Ok (Msg "wsl_version" @($wslVersion))
}

# ---------------------------------------------------------------------------------------------
Write-Step 4 "step_distro"
$installed = Get-InstalledDistros
if ($installed -contains $Distro) {
    Write-Ok (Msg "distro_present" @($Distro))
}
elseif ($DryRun) {
    Write-Info "wsl --install -d $Distro"
}
else {
    if (-not (Test-OnlineDistro -Name $Distro)) { Stop-Setup (Msg "distro_not_online" @($Distro)) }
    Write-Info (Msg "distro_installing" @($Distro))
    Write-Host "        [ !! ] " -ForegroundColor Black -BackgroundColor Yellow -NoNewline
    Write-Host " $(Msg 'distro_exit_hint')" -ForegroundColor Yellow
    Write-Host ""
    wsl.exe --install -d $Distro
    if ($LASTEXITCODE -ne 0) { Stop-Setup (Msg "distro_install_failed" @($Distro, $LASTEXITCODE)) }
}

if ($DryRun) {
    $linuxUser = "user"
    $linuxHome = "/home/user"
}
else {
    $linuxUser = ((wsl.exe -d $Distro --exec whoami 2>$null) -join "").Trim()
    $linuxHome = ((wsl.exe -d $Distro --exec printenv HOME 2>$null) -join "").Trim()
    if (-not $linuxUser -or $linuxUser -eq "root" -or -not $linuxHome) { Stop-Setup (Msg "distro_user_ko" @($Distro)) }
    Write-Ok (Msg "distro_user" @($linuxUser))

    # Never take the default away from another distribution without asking.
    $currentDefault = Get-DefaultDistro
    if ($currentDefault -ne $Distro) {
        $others = @(Get-InstalledDistros | Where-Object { $_ -ne $Distro -and $_ -notlike "docker-desktop*" })
        if ($others.Count -eq 0 -or (Read-YesNo -Question (Msg "ask_default" @($Distro, $currentDefault)) -Default $false)) {
            wsl.exe --set-default $Distro | Out-Null
            Write-Ok (Msg "default_set" @($Distro))
        }
    }
}

# ---------------------------------------------------------------------------------------------
Write-Step 5 "step_stack"
if (Read-YesNo -Question (Msg "ask_stack" @($Distro))) {
    Write-Info (Msg "stack_info")
    if ($DryRun) {
        $dryShell = if ($Shell) { " --shell $Shell" } else { "" }
        $dryFrom = if ($StackScript) { $StackScript } else { "$installHost/lamp" }
        Write-Info "$dryFrom -> bash lamp-lapp-stack.sh --yes$dryShell"
    }
    else {
        # Downloaded on the Windows side: the Debian image has neither curl nor wget.
        $stackCopy = Join-Path $workDir "lamp-lapp-stack.sh"
        if ($StackScript) {
            Copy-Item -LiteralPath $StackScript -Destination $stackCopy -Force
            Write-Info (Msg "stack_local" @($StackScript))
        }
        else {
            try { Invoke-Download -Url "$installHost/lamp" -Output $stackCopy }
            catch { Stop-Setup (Msg "stack_download_ko" @($_.Exception.Message)) }
        }

        # Plain calls instead of an inline "bash -c": PowerShell 5.1 does not escape quotes inside native arguments.
        $linuxScript = ((wsl.exe -d $Distro --exec wslpath -u $stackCopy) -join "").Trim()
        $stackArguments = @("--yes")
        if ($Shell) { $stackArguments += @("--shell", $Shell) }
        Write-Host ""
        wsl.exe -d $Distro --cd "~" --exec bash $linuxScript @stackArguments
        $stackExit = $LASTEXITCODE
        Write-Host ""
        if ($stackExit -ne 0) { Stop-Setup (Msg "stack_ko" @($stackExit, $Distro)) }
        Write-Ok (Msg "stack_ok")
        Write-Info (Msg "distro_restart" @($Distro))
        wsl.exe --terminate $Distro | Out-Null
    }
}
else {
    Write-Info (Msg "stack_skipped")
}

# ---------------------------------------------------------------------------------------------
Write-Step 6 "step_docker"
$dockerInstalled = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
    Get-ItemProperty -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Docker Desktop*" }
if ($dockerInstalled) {
    Write-Ok (Msg "docker_present")
}
elseif (Read-YesNo -Question (Msg "ask_docker") -Default $false) {
    if ($DryRun) {
        Write-Info "Docker Desktop Installer.exe install --accept-license --quiet"
    }
    else {
        Write-Info (Msg "docker_installing")
        $dockerInstaller = Join-Path $workDir "DockerDesktopInstaller.exe"
        try { Invoke-Download -Url "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -Output $dockerInstaller }
        catch { Stop-Setup $_.Exception.Message }
        $process = Start-Process -Wait -PassThru -FilePath $dockerInstaller -ArgumentList 'install', '--accept-license', '--quiet'
        Remove-Item -Path $dockerInstaller -Force -ErrorAction SilentlyContinue
        if ($process.ExitCode -eq 0) { Write-Ok (Msg "docker_ok") } else { Write-Warn (Msg "docker_ko" @($process.ExitCode)) }
    }
}
else {
    Write-Info (Msg "stack_skipped")
}

# ---------------------------------------------------------------------------------------------
Write-Step 7 "step_shortcuts"
$homeShortcut = "$Distro Home"
if ($DryRun) {
    Write-Info "$Distro.lnk, $homeShortcut.lnk"
}
else {
    $wslExe = "$env:windir\System32\wsl.exe"
    $terminalIcon = "$wslExe,0"
    $homeIcon = "$env:windir\System32\imageres.dll,3"
    if ($Distro -like "Ubuntu*") {
        try {
            Invoke-Download -Url "$repoRawBase/icons/ubuntu-icon.ico" -Output (Join-Path $workDir "ubuntu-icon.ico")
            Invoke-Download -Url "$repoRawBase/icons/ubuntu-drive-icon.ico" -Output (Join-Path $workDir "ubuntu-drive-icon.ico")
            $terminalIcon = Join-Path $workDir "ubuntu-icon.ico"
            $homeIcon = Join-Path $workDir "ubuntu-drive-icon.ico"
        }
        catch {
            Write-Warn $_.Exception.Message
        }
    }
    New-DesktopShortcut -Name $Distro -TargetPath $wslExe -Arguments "-d $Distro --cd ~" -IconLocation $terminalIcon
    New-DesktopShortcut -Name $homeShortcut -TargetPath ("\\wsl.localhost\$Distro" + ($linuxHome -replace '/', '\')) -IconLocation $homeIcon
    Write-Ok (Msg "shortcuts_ok" @($Distro, $homeShortcut))
}

# ---------------------------------------------------------------------------------------------
Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
$line = "=" * 64
Write-Host ""
Write-Host "  $line" -ForegroundColor DarkGreen
Write-Host "   $(Msg 'done_title')" -ForegroundColor Green
Write-Host "  $line" -ForegroundColor DarkGreen
Write-Host "   $(Msg 'done_open' @($Distro))"
Write-Host "   $(Msg 'done_site')"
Write-Host "   $(Msg 'done_hosts')"
Write-Host "   $(Msg 'done_guide')" -ForegroundColor Gray
Write-Host "   $(Msg 'log_file' @($logFile))" -ForegroundColor DarkGray
Write-Host ""
Stop-Transcript | Out-Null
if (-not $Unattended) {
    Write-Host "  $(Msg 'press_enter_exit')" -ForegroundColor Gray
    Read-Host | Out-Null
}
exit 0
