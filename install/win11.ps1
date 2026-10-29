# WSL2 + Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 setup for Windows 11 (and Windows 10 1903+ with -SkipWindowsVersionCheck)
#
# Author: Maurizio Fonte (https://www.mauriziofonte.it)
# Version: 2.1.0
# Release Date: 2023-09-04
# Last Update: 2026-10-29
# License: MIT License
#
# Usually started by the bootstrap: irm https://wsl.mauriziofonte.it | iex
# Direct use: .\win11.ps1 [-Distro Debian|Ubuntu-24.04|Ubuntu-26.04] [-Shell gash|bash-plus|zsh|fish|bash]
#                         [-VmProfile Light|Balanced|Performance|Current] [-WslMemoryGB N] [-WslProcessors N]
#                         [-WslSwapGB N] [-WslNetworking nat|mirrored] [-WslGui true|false] [-VhdSizeGB N]
#                         [-WslInitTimeout MS] [-WslAppendWindowsPath true|false] [-Unattended]
#                         [-StackScript <path>] [-DryRun] [-SkipWindowsVersionCheck] [-Force]
#
# Flow: checks and questions -> WSL (reboot only when Windows needs it, then resume by itself) -> WSL update
# -> WSL settings (%UserProfile%\.wslconfig) -> distribution -> LAMP/LAPP stack -> Docker Desktop (optional)
# -> Desktop shortcuts -> summary.
# Running it again is safe: completed steps are detected and skipped.
#
# Report issues: https://github.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup/issues

# -Distro and -Shell are validated below, not with [ValidateSet]: the attribute would stay on the variable
# and reject the empty value read back from the registry.
# -Unattended answers every question with its default and never waits for Enter; creating the Linux user of a
# new distribution still needs you. -StackScript runs a local copy of lamp-lapp-stack.sh instead of the
# released one (a copy you reviewed, or the one under test in CI).
# The -Wsl*, -VmProfile and -VhdSizeGB options answer the WSL settings questions: an explicit value wins over the
# profile and over the value already in .wslconfig. Every option is checked before anything changes.
param (
    [String]$Distro = "",
    [String]$Shell = "",
    [String]$VmProfile = "",
    [Int]$WslMemoryGB = 0,
    [Int]$WslProcessors = 0,
    [Int]$WslSwapGB = -1,
    [String]$WslNetworking = "",
    [String]$WslGui = "",
    [Int]$VhdSizeGB = -1,
    [Int]$WslInitTimeout = 0,
    [String]$WslAppendWindowsPath = "",
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
$totalSteps = 8
$supportedDistros = @("Debian", "Ubuntu-24.04", "Ubuntu-26.04")
$supportedShells = @("gash", "bash-plus", "zsh", "fish", "bash")
$supportedProfiles = @("Light", "Balanced", "Performance", "Current")
# Mirrored networking needs Windows 11 22H2.
$mirroredMinBuild = 22621
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"

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
        "ask_shell" = "Which shell do you want in the Linux terminal?"
        "shell_1" = "Bash with Gash         (recommended: helpers, PHP aliases, gash hte)"
        "shell_2" = "Bash with fzf, zoxide and the starship prompt"
        "shell_3" = "Zsh with autosuggestions and syntax highlighting"
        "shell_4" = "Fish in the terminal, Bash for the scripts"
        "shell_5" = "the distribution's Bash, unchanged"
        "ask_shell_choice" = "Your choice [1-5, Enter = 1]"
        "shell_chosen" = "Shell: {0}"
        "shell_note" = "With every shell the gash command is installed: gash hte serves the local sites."
        "step_wslconfig" = "WSL settings (.wslconfig)"
        "host_resources" = "This PC: {0} GB of RAM, {1} logical processors"
        "ask_profile" = "How much of this PC may the WSL virtual machine use?"
        "profile_Light" = "Light"
        "profile_Balanced" = "Balanced"
        "profile_Performance" = "Performance"
        "profile_values" = "{0} GB of RAM, {1} processors, {2} GB of swap"
        "profile_current" = "Keep the current values: {0}"
        "profile_reserve" = "Windows always keeps at least {0} GB of RAM and {1} processors for itself."
        "ask_choice" = "Your choice [1-{0}, Enter = {1}]"
        "profile_chosen" = "Virtual machine: {0}"
        "override" = "{0}: {1} from -{2}, instead of {3} from the profile"
        "ask_network" = "How should WSL reach the network?"
        "network_nat" = "NAT       Linux has its own private network behind Windows. Windows reaches the Linux servers through localhost; other computers on your network do not see them. The WSL default."
        "network_mirrored" = "Mirrored  Linux shares the network interfaces of Windows: localhost works in both directions, IPv6 works, VPNs work better, and other computers on your network can reach Linux servers (Windows firewall permitting). A port Windows already uses cannot be used in Linux."
        "network_current" = "Now: {0}"
        "network_no_mirrored" = "Networking: NAT (mirrored needs Windows 11 22H2 or later)"
        "network_chosen" = "Networking: {0}"
        "ask_gui" = "Do you run Linux applications with a window (WSLg)? Turning them off saves memory."
        "ask_vhd" = "Limit the disk space the distribution can use? Without a limit its virtual disk can grow up to 1 TB."
        "vhd_free" = "Free space on {0}: {1} GB"
        "ask_vhd_size" = "Maximum size in GB [{0}-{1}, Enter = {2}]"
        "vhd_invalid" = "Enter a whole number from {0} to {1}."
        "vhd_chosen" = "Disk limit: {0} GB"
        "vhd_none" = "Disk limit: none"
        "wslconfig_new" = "{0} does not exist: it is created with these settings"
        "wslconfig_diff" = "{0} exists. These settings change (everything else in it stays):"
        "wslconfig_same" = "{0} already has these settings"
        "wslconfig_untouched" = "{0} exists and no WSL option was given: kept as it is"
        "ask_wslconfig_apply" = "Apply these changes? A backup copy of the file is kept."
        "wslconfig_written" = "{0} written"
        "wslconfig_backup" = "Backup: {0}"
        "wslconfig_kept" = "{0} kept as it is"
        "ask_wsl_shutdown" = "WSL must restart to use the new settings, and these distributions stop: {0}. Restart it now?"
        "wsl_shutdown_done" = "WSL restarted: the new settings are in use"
        "wsl_shutdown_later" = "The new settings apply after  wsl --shutdown"
        "vhd_set" = "Disk of {0} limited to {1} GB"
        "vhd_same" = "The disk of {0} is already limited to {1} GB"
        "vhd_ko" = "Cannot limit the disk of {0} to {1} GB (exit code {2}). Run 'wsl --manage {0} --resize {1}GB' to see the error."
        "vhd_old" = "WSL {0} cannot limit the disk of a distribution (2.5 or later is needed): no limit set"
        "ask_vhd_shutdown" = "Limiting the disk needs WSL stopped, and these distributions stop: {0}. Stop WSL now?"
        "vhd_later" = "Disk of {0} not limited: run this setup again when WSL can stop"
        "invalid_options" = "invalid options, nothing was changed"
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
        "network_ok" = "{0} reaches the Internet (github.com resolves)"
        "network_ko" = "{0} cannot resolve github.com, and the stack installer needs the Internet. DNS servers in {0}: {1}"
        "network_mirrored_ko" = "{0} cannot resolve github.com with mirrored networking"
        "ask_network_nat" = "Try NAT networking instead? WSL restarts, and every running distribution stops."
        "network_fallback" = "Mirrored networking does not work on this PC, NAT does: .wslconfig now says networkingMode=nat. To try mirrored again later: -WslNetworking mirrored"
        "network_fallback_ko" = "NAT does not work either: .wslconfig is back to mirrored networking"
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
        "ask_shell" = "Quale shell vuoi nel terminale Linux?"
        "shell_1" = "Bash con Gash          (consigliata: funzioni, alias PHP, gash hte)"
        "shell_2" = "Bash con fzf, zoxide e il prompt starship"
        "shell_3" = "Zsh con suggerimenti automatici ed evidenziazione della sintassi"
        "shell_4" = "Fish nel terminale, Bash per gli script"
        "shell_5" = "la Bash della distribuzione, senza modifiche"
        "ask_shell_choice" = "La tua scelta [1-5, Invio = 1]"
        "shell_chosen" = "Shell: {0}"
        "shell_note" = "Con ogni shell viene installato il comando gash: gash hte serve i siti locali."
        "step_wslconfig" = "Impostazioni di WSL (.wslconfig)"
        "host_resources" = "Questo PC: {0} GB di RAM, {1} processori logici"
        "ask_profile" = "Quanta parte di questo PC può usare la macchina virtuale di WSL?"
        "profile_Light" = "Leggero"
        "profile_Balanced" = "Bilanciato"
        "profile_Performance" = "Prestazioni"
        "profile_values" = "{0} GB di RAM, {1} processori, {2} GB di swap"
        "profile_current" = "Mantieni i valori attuali: {0}"
        "profile_reserve" = "Windows tiene sempre per sé almeno {0} GB di RAM e {1} processori."
        "ask_choice" = "La tua scelta [1-{0}, Invio = {1}]"
        "profile_chosen" = "Macchina virtuale: {0}"
        "override" = "{0}: {1} da -{2}, al posto di {3} del profilo"
        "ask_network" = "Come deve accedere alla rete WSL?"
        "network_nat" = "NAT       Linux ha una sua rete privata dietro Windows. Windows raggiunge i server Linux tramite localhost; gli altri computer della tua rete non li vedono. È il valore predefinito di WSL."
        "network_mirrored" = "Mirrored  Linux condivide le interfacce di rete di Windows: localhost funziona nei due sensi, IPv6 funziona, le VPN funzionano meglio, e gli altri computer della tua rete possono raggiungere i server Linux (se il firewall di Windows lo consente). Una porta già usata da Windows non è utilizzabile in Linux."
        "network_current" = "Ora: {0}"
        "network_no_mirrored" = "Rete: NAT (mirrored richiede Windows 11 22H2 o successivo)"
        "network_chosen" = "Rete: {0}"
        "ask_gui" = "Usi applicazioni Linux con una finestra (WSLg)? Disattivarle fa risparmiare memoria."
        "ask_vhd" = "Limitare lo spazio disco che la distribuzione può usare? Senza limite il suo disco virtuale può crescere fino a 1 TB."
        "vhd_free" = "Spazio libero su {0}: {1} GB"
        "ask_vhd_size" = "Dimensione massima in GB [{0}-{1}, Invio = {2}]"
        "vhd_invalid" = "Inserisci un numero intero da {0} a {1}."
        "vhd_chosen" = "Limite del disco: {0} GB"
        "vhd_none" = "Limite del disco: nessuno"
        "wslconfig_new" = "{0} non esiste: viene creato con queste impostazioni"
        "wslconfig_diff" = "{0} esiste. Cambiano queste impostazioni (tutto il resto del file rimane):"
        "wslconfig_same" = "{0} ha già queste impostazioni"
        "wslconfig_untouched" = "{0} esiste e non è stata data nessuna opzione WSL: viene mantenuto così com'è"
        "ask_wslconfig_apply" = "Applicare queste modifiche? Viene conservata una copia di backup del file."
        "wslconfig_written" = "{0} scritto"
        "wslconfig_backup" = "Backup: {0}"
        "wslconfig_kept" = "{0} mantenuto così com'è"
        "ask_wsl_shutdown" = "WSL deve riavviarsi per usare le nuove impostazioni, e queste distribuzioni si fermano: {0}. Riavviarlo adesso?"
        "wsl_shutdown_done" = "WSL riavviato: le nuove impostazioni sono in uso"
        "wsl_shutdown_later" = "Le nuove impostazioni valgono dopo  wsl --shutdown"
        "vhd_set" = "Disco di {0} limitato a {1} GB"
        "vhd_same" = "Il disco di {0} è già limitato a {1} GB"
        "vhd_ko" = "Impossibile limitare il disco di {0} a {1} GB (codice di uscita {2}). Esegui 'wsl --manage {0} --resize {1}GB' per vedere l'errore."
        "vhd_old" = "WSL {0} non può limitare il disco di una distribuzione (serve la 2.5 o successiva): nessun limite impostato"
        "ask_vhd_shutdown" = "Per limitare il disco WSL deve fermarsi, e queste distribuzioni si fermano: {0}. Fermare WSL ora?"
        "vhd_later" = "Disco di {0} non limitato: esegui di nuovo questa installazione quando WSL può fermarsi"
        "invalid_options" = "opzioni non valide, non è stato cambiato nulla"
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
        "network_ok" = "{0} raggiunge Internet (github.com viene risolto)"
        "network_ko" = "{0} non riesce a risolvere github.com, e l'installer dello stack ha bisogno di Internet. Server DNS in {0}: {1}"
        "network_mirrored_ko" = "{0} non riesce a risolvere github.com con la rete mirrored"
        "ask_network_nat" = "Provare invece la rete NAT? WSL si riavvia, e ogni distribuzione in esecuzione si ferma."
        "network_fallback" = "La rete mirrored non funziona su questo PC, la NAT sì: ora .wslconfig dice networkingMode=nat. Per riprovare la mirrored più avanti: -WslNetworking mirrored"
        "network_fallback_ko" = "Nemmeno la NAT funziona: .wslconfig torna alla rete mirrored"
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
    if ($VmProfile) { $list += @("-VmProfile", $VmProfile) }
    if ($WslMemoryGB -ne 0) { $list += @("-WslMemoryGB", $WslMemoryGB) }
    if ($WslProcessors -ne 0) { $list += @("-WslProcessors", $WslProcessors) }
    if ($WslSwapGB -ne -1) { $list += @("-WslSwapGB", $WslSwapGB) }
    if ($WslNetworking) { $list += @("-WslNetworking", $WslNetworking) }
    if ($WslGui) { $list += @("-WslGui", $WslGui) }
    if ($VhdSizeGB -ne -1) { $list += @("-VhdSizeGB", $VhdSizeGB) }
    if ($WslInitTimeout -ne 0) { $list += @("-WslInitTimeout", $WslInitTimeout) }
    if ($WslAppendWindowsPath) { $list += @("-WslAppendWindowsPath", $WslAppendWindowsPath) }
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

function Get-RunningDistros {
    return @(wsl.exe --list --running --quiet 2>$null | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
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

# Whether the distribution resolves a public name: without DNS the stack installer stalls for minutes on each download.
function Test-DistroNetwork {
    param ([Parameter(Mandatory = $true)] [String]$Name)
    wsl.exe -d $Name -u root --exec timeout 20 getent hosts github.com | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Writes .wslconfig with a new network mode and restarts WSL, so that the next start uses it.
function Set-WslNetworking {
    param ([String]$Mode)
    $text = [IO.File]::ReadAllText($wslConfigPath)
    $settings = @(Get-WslSettings -Networking $Mode -Base $false -VhdSizeGB 0 | Where-Object { $_.Key -eq "networkingMode" })
    [IO.File]::WriteAllText($wslConfigPath, (Merge-IniText -Text $text -Settings $settings), (New-Object System.Text.UTF8Encoding($false)))
    wsl.exe --shutdown | Out-Null
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
# WSL settings. The functions down to Get-WslSettings compute without side effects: CI tests them on their own.

# Three sizes for the WSL virtual machine, from the RAM installed (the share) and the RAM Windows can use (the
# ceiling): Windows keeps at least 6 GB (half the RAM on smaller PCs) and 2 logical processors.
function Get-VmProfiles {
    param ([Double]$InstalledGB, [Double]$UsableGB, [Int]$Threads)
    $reserveGB = [Math]::Min(6, [Math]::Floor($UsableGB / 2))
    $maxMemory = [Math]::Max(1, [Math]::Floor($UsableGB) - $reserveGB)
    $maxCpu = [Math]::Max(1, $Threads - 2)
    $shares = @(
        @{ Name = "Light"; Memory = 0.25; Cpu = 0.25; CpuMin = 2 },
        @{ Name = "Balanced"; Memory = 0.5; Cpu = 0.5; CpuMin = 1 },
        @{ Name = "Performance"; Memory = 0.7; Cpu = 0.75; CpuMin = 1 }
    )
    foreach ($share in $shares) {
        $memory = [Math]::Min($maxMemory, [Math]::Max(2, [Math]::Floor($InstalledGB * $share.Memory)))
        $cpu = [Math]::Min($maxCpu, [Math]::Max($share.CpuMin, [Math]::Floor($Threads * $share.Cpu)))
        [PSCustomObject]@{
            Name       = $share.Name
            MemoryGB   = [Int]$memory
            Processors = [Int]$cpu
            SwapGB     = Get-SwapGB -MemoryGB $memory
        }
    }
}

# Swap: half the RAM of the virtual machine, from 1 to 8 GB (the swap file lives on the Windows disk).
function Get-SwapGB {
    param ([Double]$MemoryGB)
    return [Int][Math]::Min(8, [Math]::Max(1, [Math]::Floor($MemoryGB / 2)))
}

# The proposed disk limit: half the space available, rounded down to 512, 256, 128 or 64 GB.
function Get-VhdProposal {
    param ([Int]$AvailableGB)
    $half = [Math]::Floor($AvailableGB / 2)
    foreach ($size in @(512, 256, 128, 64)) { if ($half -ge $size) { return $size } }
    return [Int][Math]::Max(16, $half)
}

# The values of an INI text, as "section.key" (lower case) -> value.
function Read-IniValues {
    param ([String]$Text)
    $values = @{}
    $section = ""
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') { $section = $Matches[1].Trim().ToLower(); continue }
        if ($line -match '^\s*[#;]') { continue }
        if ($line -match '^\s*([^=\s]+)\s*=\s*(.*?)\s*$') {
            $name = "$section.$($Matches[1].ToLower())"
            if (-not $values.ContainsKey($name)) { $values[$name] = $Matches[2] }
        }
    }
    return $values
}

# Sets each setting (Section, Key, Value, Comment) in an INI text and keeps every other line: a key already
# there gets the new value in place, a new key goes at the end of its section (after its comment), a missing
# section is added at the end.
function Merge-IniText {
    param ([String]$Text, [Object[]]$Settings)
    $lines = New-Object System.Collections.Generic.List[String]
    if ($Text) { foreach ($line in ($Text.TrimEnd("`r", "`n") -split "`r?`n")) { $lines.Add($line) } }
    foreach ($setting in $Settings) {
        $start = -1
        $end = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*\[([^\]]+)\]\s*$') {
                if ($start -ge 0) { $end = $i; break }
                if ($Matches[1].Trim() -ieq $setting.Section) { $start = $i }
            }
        }
        $entry = "$($setting.Key)=$($setting.Value)"
        if ($start -lt 0) {
            if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne "") { $lines.Add("") }
            $lines.Add("[$($setting.Section)]")
            if ($setting.Comment) { $lines.Add("# $($setting.Comment)") }
            $lines.Add($entry)
            continue
        }
        $found = -1
        for ($i = $start + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match ('^\s*' + [Regex]::Escape($setting.Key) + '\s*=')) { $found = $i; break }
        }
        if ($found -ge 0) {
            $lines[$found] = $entry
            continue
        }
        $at = $start + 1
        for ($i = $end - 1; $i -gt $start; $i--) {
            if ($lines[$i].Trim() -ne "") { $at = $i + 1; break }
        }
        if ($setting.Comment) { $lines.Insert($at, "# $($setting.Comment)"); $at++ }
        $lines.Insert($at, $entry)
    }
    return (($lines -join "`r`n") + "`r`n")
}

# The settings whose value differs from the INI text, as "[section] key: old -> new".
function Get-IniChange {
    param ([String]$Text, [Object[]]$Settings)
    $current = Read-IniValues -Text $Text
    foreach ($setting in $Settings) {
        $name = "$($setting.Section.ToLower()).$($setting.Key.ToLower())"
        $old = if ($current.ContainsKey($name)) { $current[$name] } else { $null }
        if ($null -ne $old -and $old -ieq "$($setting.Value)") { continue }
        $shown = if ($null -eq $old) { "-" } else { $old }
        "[$($setting.Section)] $($setting.Key): $shown -> $($setting.Value)"
    }
}

# The .wslconfig settings for the chosen values; a $null value leaves that setting as it is.
function Get-WslSettings {
    param ($MemoryGB, $Processors, $SwapGB, [String]$Networking, $Gui, [Bool]$Base, [Int]$VhdSizeGB)
    $list = @()
    if ($null -ne $MemoryGB) { $list += @{ Section = "wsl2"; Key = "memory"; Value = "$($MemoryGB)GB"; Comment = "RAM of the WSL virtual machine" } }
    if ($null -ne $Processors) { $list += @{ Section = "wsl2"; Key = "processors"; Value = "$Processors"; Comment = "Logical processors of the WSL virtual machine" } }
    if ($null -ne $SwapGB) { $list += @{ Section = "wsl2"; Key = "swap"; Value = "$($SwapGB)GB"; Comment = "Swap file of the WSL virtual machine, on the Windows disk" } }
    if ($Networking) {
        $list += @{ Section = "wsl2"; Key = "networkingMode"; Value = $Networking; Comment = "nat: a private network behind Windows; mirrored: the network interfaces of Windows" }
        if ($Networking -eq "mirrored") {
            $list += @{ Section = "wsl2"; Key = "dnsTunneling"; Value = "true"; Comment = "" }
            $list += @{ Section = "wsl2"; Key = "autoProxy"; Value = "true"; Comment = "" }
            $list += @{ Section = "wsl2"; Key = "firewall"; Value = "true"; Comment = "" }
        }
    }
    if ($null -ne $Gui) { $list += @{ Section = "wsl2"; Key = "guiApplications"; Value = $(if ($Gui) { "true" } else { "false" }); Comment = "WSLg: Linux applications with a window" } }
    if ($Base) {
        $list += @{ Section = "wsl2"; Key = "maxCrashDumpCount"; Value = "3"; Comment = "Crash dumps kept in %Temp%\wsl-crashes" }
    }
    if ($VhdSizeGB -gt 0) { $list += @{ Section = "wsl2"; Key = "defaultVhdSize"; Value = "$($VhdSizeGB)GB"; Comment = "Maximum size of the virtual disk of new distributions" } }
    if ($Base) {
        $list += @{ Section = "experimental"; Key = "sparseVhd"; Value = "true"; Comment = "New virtual disks are sparse: space freed inside Linux goes back to Windows" }
        $list += @{ Section = "experimental"; Key = "autoMemoryReclaim"; Value = "dropCache"; Comment = "Give cached memory back to Windows when the VM is idle" }
    }
    return $list
}

function Get-HostResources {
    $system = Get-CimInstance -ClassName Win32_ComputerSystem
    $usable = $system.TotalPhysicalMemory / 1GB
    $installed = ((Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum).Sum) / 1GB
    if (-not $installed -or $installed -lt $usable) { $installed = $usable }
    return [PSCustomObject]@{
        InstalledGB = [Math]::Round($installed, 1)
        UsableGB    = [Math]::Round($usable, 1)
        Threads     = [Int]$system.NumberOfLogicalProcessors
    }
}

# Where the virtual disk of the distribution is (or will be): its drive, the free space there and the size of
# its file, so that the limit can at most take all the space that is left.
function Get-DistroDisk {
    param ([String]$Name)
    $folder = $env:LOCALAPPDATA
    $fileGB = 0
    $lxss = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    foreach ($key in (Get-ChildItem -Path $lxss -ErrorAction SilentlyContinue)) {
        $entry = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if ($entry.DistributionName -eq $Name -and $entry.BasePath) {
            $folder = $entry.BasePath -replace '^\\\\\?\\', ''
            $vhdx = Join-Path $folder "ext4.vhdx"
            if (Test-Path -LiteralPath $vhdx) { $fileGB = (Get-Item -LiteralPath $vhdx).Length / 1GB }
        }
    }
    $drive = Split-Path -Path $folder -Qualifier
    $freeGB = (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue).FreeSpace / 1GB
    return [PSCustomObject]@{
        Drive       = $drive
        AvailableGB = [Int][Math]::Floor($freeGB + $fileGB)
    }
}

# Whether the root file system of a distribution is already limited to this size: a little less than its
# disk (the ext4 metadata), never more.
function Test-DistroDiskSize {
    param ([String]$Name, [Int]$SizeGB)
    $bytes = "$((wsl.exe -d $Name -u root --exec df -B1 --output=size / 2>$null) | Select-Object -Last 1)".Trim()
    if ($bytes -notmatch '^\d+$') { return $false }
    return ([Int64]$bytes -le [Int64]$SizeGB * 1GB -and [Int64]$bytes -ge [Int64]$SizeGB * 1GB * 0.9)
}

# Space in GB used inside a distribution (0 when unknown). A distribution started only to measure it is
# stopped again, so that applying .wslconfig later does not have to ask.
function Get-DistroUsedGB {
    param ([String]$Name)
    $wasRunning = (Get-RunningDistros) -contains $Name
    $bytes = ((wsl.exe -d $Name -u root --exec df -B1 --output=used / 2>$null) | Select-Object -Last 1)
    if (-not $wasRunning) { wsl.exe --terminate $Name 2>$null | Out-Null }
    if ("$bytes".Trim() -match '^\d+$') { return [Int][Math]::Ceiling([Int64]"$bytes".Trim() / 1GB) }
    return 0
}

function Read-Choice {
    param ([Int]$Count, [Int]$Default)
    if ($Unattended) { return $Default }
    Write-Host "        $(Msg 'ask_choice' @($Count, $Default)): " -NoNewline
    $answer = (Read-Host).Trim()
    if ($answer -match '^\d+$' -and [Int]$answer -ge 1 -and [Int]$answer -le $Count) { return [Int]$answer }
    return $Default
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

# Every option is checked before anything changes; all the problems are listed at once.
$hostInfo = Get-HostResources
$installedNow = @(); if (Get-WslVersion) { $installedNow = Get-InstalledDistros }
$problems = @()
if ($Distro -and $supportedDistros -notcontains $Distro) { $problems += "-Distro: $($supportedDistros -join ', ')" }
if ($Shell -and $supportedShells -notcontains $Shell) { $problems += "-Shell: $($supportedShells -join ', ')" }
if ($StackScript -and -not (Test-Path -LiteralPath $StackScript -PathType Leaf)) { $problems += "-StackScript: $StackScript" }
if ($VmProfile -and $supportedProfiles -notcontains $VmProfile) { $problems += "-VmProfile: $($supportedProfiles -join ', ')" }
$maxMemoryGB = [Int][Math]::Floor($hostInfo.UsableGB) - 2
if ($WslMemoryGB -ne 0 -and ($WslMemoryGB -lt 2 -or $WslMemoryGB -gt $maxMemoryGB)) { $problems += "-WslMemoryGB: from 2 to $maxMemoryGB" }
if ($WslProcessors -ne 0 -and ($WslProcessors -lt 1 -or $WslProcessors -gt $hostInfo.Threads)) { $problems += "-WslProcessors: from 1 to $($hostInfo.Threads)" }
if ($WslSwapGB -lt -1 -or $WslSwapGB -gt 64) { $problems += "-WslSwapGB: from 0 to 64" }
if ($WslNetworking -and @("nat", "mirrored") -notcontains $WslNetworking) { $problems += "-WslNetworking: nat, mirrored" }
if ($WslNetworking -eq "mirrored" -and $build -lt $mirroredMinBuild) { $problems += "-WslNetworking mirrored: needs Windows 11 22H2 (build $mirroredMinBuild) or later" }
if ($WslGui -and @("true", "false") -notcontains $WslGui) { $problems += "-WslGui: true, false" }
if ($WslInitTimeout -ne 0 -and ($WslInitTimeout -lt 1000 -or $WslInitTimeout -gt 600000)) { $problems += "-WslInitTimeout: from 1000 to 600000 (milliseconds)" }
if ($WslAppendWindowsPath -and @("true", "false") -notcontains $WslAppendWindowsPath) { $problems += "-WslAppendWindowsPath: true, false" }
$checkDistro = if ($Distro) { $Distro } else { [String](Get-SetupValue -Key "Distro") }
$disk = Get-DistroDisk -Name $checkDistro
# An existing distribution keeps its files: its limit leaves at least 4 GB free above what it uses.
$vhdMinGB = 16
if ($checkDistro -and $installedNow -contains $checkDistro -and ($VhdSizeGB -gt 0 -or ($VhdSizeGB -lt 0 -and -not $Unattended))) {
    $vhdMinGB = [Math]::Max(16, (Get-DistroUsedGB -Name $checkDistro) + 4)
}
if ($VhdSizeGB -lt -1 -or ($VhdSizeGB -gt 0 -and ($VhdSizeGB -lt $vhdMinGB -or $VhdSizeGB -gt $disk.AvailableGB))) {
    $problems += "-VhdSizeGB: 0 (no limit) or from $vhdMinGB to $($disk.AvailableGB)"
}
if ($problems.Count -gt 0) {
    foreach ($problem in $problems) { Write-Warn $problem }
    Stop-Setup (Msg "invalid_options")
}
$WslNetworking = "$WslNetworking".ToLower()
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

if (-not $Shell -and -not $Unattended) {
    Write-Host ""
    Write-Host "        $(Msg 'ask_shell')" -ForegroundColor White
    for ($i = 1; $i -le 5; $i++) { Write-Host "          $i) $(Msg "shell_$i")" }
    Write-Host "        $(Msg 'ask_shell_choice'): " -NoNewline
    $Shell = switch ((Read-Host).Trim()) { "2" { "bash-plus" } "3" { "zsh" } "4" { "fish" } "5" { "bash" } default { "gash" } }
}
if ($Shell) {
    Write-Ok (Msg "shell_chosen" @($Shell))
    if ($Shell -ne "gash") { Write-Info (Msg "shell_note") }
}

# WSL settings: the answers become options, so that the resume after a reboot does not ask again.
$wslConfigText = ""
if (Test-Path -LiteralPath $wslConfigPath) { $wslConfigText = [IO.File]::ReadAllText($wslConfigPath) }
$wslConfigExists = Test-Path -LiteralPath $wslConfigPath
$current = Read-IniValues -Text $wslConfigText
$profiles = @(Get-VmProfiles -InstalledGB $hostInfo.InstalledGB -UsableGB $hostInfo.UsableGB -Threads $hostInfo.Threads)
# Unattended on a PC that already has a .wslconfig: only what the options say changes.
$onlyExplicit = $Unattended -and $wslConfigExists
Write-Host ""
Write-Info (Msg "host_resources" @($hostInfo.InstalledGB, $hostInfo.Threads))

$currentValues = @()
foreach ($key in @("memory", "processors", "swap")) {
    if ($current.ContainsKey("wsl2.$key")) { $currentValues += "$key=$($current["wsl2.$key"])" }
}
if (-not $VmProfile -and -not $onlyExplicit) {
    if ($Unattended) {
        $VmProfile = "Balanced"
    }
    else {
        Write-Host ""
        Write-Host "        $(Msg 'ask_profile')" -ForegroundColor White
        for ($i = 0; $i -lt 3; $i++) {
            $p = $profiles[$i]
            Write-Host ("          {0}) {1,-12} {2}" -f ($i + 1), (Msg "profile_$($p.Name)"), (Msg "profile_values" @($p.MemoryGB, $p.Processors, $p.SwapGB)))
        }
        $count = 3
        $default = 2
        if ($currentValues.Count -gt 0) {
            Write-Host ("          4) " + (Msg "profile_current" @($currentValues -join ", ")))
            $count = 4
            $default = 4
        }
        $reserve = [Math]::Min(6, [Math]::Floor($hostInfo.UsableGB / 2))
        Write-Host "          $(Msg 'profile_reserve' @($reserve, 2))" -ForegroundColor DarkGray
        $VmProfile = @("Light", "Balanced", "Performance", "Current")[(Read-Choice -Count $count -Default $default) - 1]
    }
}
$vm = @{ MemoryGB = $null; Processors = $null; SwapGB = $null }
$chosenProfile = $profiles | Where-Object { $_.Name -eq $VmProfile }
if ($chosenProfile) {
    $vm.MemoryGB = $chosenProfile.MemoryGB
    $vm.Processors = $chosenProfile.Processors
    $vm.SwapGB = $chosenProfile.SwapGB
}
# An explicit value wins over the profile; the swap follows an explicit RAM size unless it is explicit too.
foreach ($override in @(@("MemoryGB", $WslMemoryGB, "WslMemoryGB", 0), @("Processors", $WslProcessors, "WslProcessors", 0), @("SwapGB", $WslSwapGB, "WslSwapGB", -1))) {
    if ($override[1] -gt $override[3]) {
        if ($chosenProfile) { Write-Info (Msg "override" @($override[0], $override[1], $override[2], $vm[$override[0]])) }
        $vm[$override[0]] = $override[1]
    }
}
if ($WslMemoryGB -gt 0 -and $WslSwapGB -lt 0 -and $chosenProfile) { $vm.SwapGB = Get-SwapGB -MemoryGB $WslMemoryGB }
if ($VmProfile -eq "Current") {
    Write-Ok (Msg "profile_chosen" @(Msg "profile_current" @($currentValues -join ", ")))
}
elseif ($VmProfile) {
    $values = Msg "profile_values" @($vm.MemoryGB, $vm.Processors, $vm.SwapGB)
    Write-Ok (Msg "profile_chosen" @("$(Msg "profile_$VmProfile") ($values)"))
}

$currentNetwork = if ($current.ContainsKey("wsl2.networkingmode")) { $current["wsl2.networkingmode"].ToLower() } else { "nat" }
if (-not $WslNetworking -and -not $onlyExplicit) {
    if ($build -lt $mirroredMinBuild) {
        $WslNetworking = "nat"
        Write-Info (Msg "network_no_mirrored")
    }
    elseif ($Unattended) {
        $WslNetworking = "nat"
    }
    else {
        Write-Host ""
        Write-Host "        $(Msg 'ask_network')" -ForegroundColor White
        Write-Host "          1) $(Msg 'network_nat')"
        Write-Host "          2) $(Msg 'network_mirrored')"
        if ($wslConfigExists) { Write-Host "          $(Msg 'network_current' @($currentNetwork))" -ForegroundColor DarkGray }
        $WslNetworking = @("nat", "mirrored")[(Read-Choice -Count 2 -Default $(if ($currentNetwork -eq "mirrored") { 2 } else { 1 })) - 1]
    }
}
if ($WslNetworking) { Write-Ok (Msg "network_chosen" @($WslNetworking)) }

if (-not $WslGui -and -not $onlyExplicit) {
    $currentGui = $current.ContainsKey("wsl2.guiapplications") -and $current["wsl2.guiapplications"] -ieq "true"
    $WslGui = if (Read-YesNo -Question (Msg "ask_gui") -Default $currentGui) { "true" } else { "false" }
}

if ($VhdSizeGB -lt 0 -and -not $onlyExplicit) {
    $VhdSizeGB = 0
    if ($disk.AvailableGB -ge $vhdMinGB -and (Read-YesNo -Question (Msg "ask_vhd") -Default $false)) {
        Write-Info (Msg "vhd_free" @($disk.Drive, $disk.AvailableGB))
        $proposal = [Math]::Min($disk.AvailableGB, [Math]::Max($vhdMinGB, (Get-VhdProposal -AvailableGB $disk.AvailableGB)))
        while ($true) {
            Write-Host "        $(Msg 'ask_vhd_size' @($vhdMinGB, $disk.AvailableGB, $proposal)): " -NoNewline
            $answer = (Read-Host).Trim()
            if ($answer -eq "") { $VhdSizeGB = $proposal; break }
            if ($answer -match '^\d+$' -and [Int]$answer -ge $vhdMinGB -and [Int]$answer -le $disk.AvailableGB) { $VhdSizeGB = [Int]$answer; break }
            Write-Warn (Msg "vhd_invalid" @($vhdMinGB, $disk.AvailableGB))
        }
    }
}
if ($VhdSizeGB -gt 0) { Write-Ok (Msg "vhd_chosen" @($VhdSizeGB)) } elseif ($VhdSizeGB -eq 0) { Write-Ok (Msg "vhd_none") }

$gui = if ($WslGui) { $WslGui -eq "true" } else { $null }
$wslSettings = @(Get-WslSettings -MemoryGB $vm.MemoryGB -Processors $vm.Processors -SwapGB $vm.SwapGB -Networking $WslNetworking -Gui $gui -Base (-not $onlyExplicit) -VhdSizeGB $VhdSizeGB)

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
# Before the distribution: a new virtual disk is born sparse only when sparseVhd is already in force.
Write-Step 4 "step_wslconfig"
$wslConfigChanged = $false
$changes = @(Get-IniChange -Text $wslConfigText -Settings $wslSettings)
if ($wslSettings.Count -eq 0) {
    Write-Ok (Msg "wslconfig_untouched" @($wslConfigPath))
}
elseif ($changes.Count -eq 0) {
    Write-Ok (Msg "wslconfig_same" @($wslConfigPath))
}
else {
    Write-Info (Msg $(if ($wslConfigExists) { "wslconfig_diff" } else { "wslconfig_new" }) @($wslConfigPath))
    foreach ($change in $changes) { Write-Host "               $change" }
    # Unattended, the options given are the answer: they win over the values in the file.
    if (-not $wslConfigExists -or (Read-YesNo -Question (Msg "ask_wslconfig_apply") -Default $true)) {
        if (-not $DryRun) {
            if ($wslConfigExists) {
                $backup = "$wslConfigPath.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
                Copy-Item -LiteralPath $wslConfigPath -Destination $backup
                Write-Info (Msg "wslconfig_backup" @($backup))
            }
            [IO.File]::WriteAllText($wslConfigPath, (Merge-IniText -Text $wslConfigText -Settings $wslSettings), (New-Object System.Text.UTF8Encoding($false)))
        }
        Write-Ok (Msg "wslconfig_written" @($wslConfigPath))
        $wslConfigChanged = $true
    }
    else {
        Write-Info (Msg "wslconfig_kept" @($wslConfigPath))
    }
}
if ($wslConfigChanged -and -not $DryRun) {
    $running = Get-RunningDistros
    if ($running.Count -eq 0) {
        # Nothing runs: the next start reads the new file. A VM still idling is stopped all the same.
        wsl.exe --shutdown | Out-Null
    }
    elseif (Read-YesNo -Question (Msg "ask_wsl_shutdown" @($running -join ", ")) -Default $true) {
        wsl.exe --shutdown | Out-Null
        Write-Ok (Msg "wsl_shutdown_done")
    }
    else {
        Write-Warn (Msg "wsl_shutdown_later")
    }
}

# ---------------------------------------------------------------------------------------------
Write-Step 5 "step_distro"
$installed = Get-InstalledDistros
# wsl --install --vhd-size and wsl --manage --resize arrived with WSL 2.5.
if ($VhdSizeGB -gt 0 -and -not $DryRun -and [Version]$wslVersion -lt [Version]"2.5.0") {
    Write-Warn (Msg "vhd_old" @($wslVersion))
    $VhdSizeGB = 0
}
# --web-download: the image comes from the distribution's own download site, not the Microsoft Store,
# which is missing or blocked on some Windows editions and company PCs.
$installArguments = @("--web-download")
if ($VhdSizeGB -gt 0) { $installArguments += @("--vhd-size", "$($VhdSizeGB)GB") }
if ($installed -contains $Distro) {
    Write-Ok (Msg "distro_present" @($Distro))
    if ($VhdSizeGB -gt 0) {
        if ($DryRun) {
            Write-Info "wsl --manage $Distro --resize $($VhdSizeGB)GB"
        }
        elseif (Test-DistroDiskSize -Name $Distro -SizeGB $VhdSizeGB) {
            Write-Ok (Msg "vhd_same" @($Distro, $VhdSizeGB))
        }
        else {
            # The virtual disk stays attached to the WSL virtual machine after "wsl --terminate": only a
            # stopped WSL lets it go (WSL_E_DISTRO_NOT_STOPPED otherwise).
            $running = @(Get-RunningDistros | Where-Object { $_ -ne $Distro })
            if ($running.Count -eq 0 -or (Read-YesNo -Question (Msg "ask_vhd_shutdown" @($running -join ", ")) -Default $true)) {
                for ($try = 1; $try -le 3; $try++) {
                    wsl.exe --shutdown | Out-Null
                    Start-Sleep -Seconds (2 * $try)
                    $resizeOutput = (wsl.exe --manage $Distro --resize "$($VhdSizeGB)GB" 2>&1) -join " "
                    $resizeExit = $LASTEXITCODE
                    if ($resizeExit -eq 0) { break }
                }
                if ($resizeExit -eq 0) { Write-Ok (Msg "vhd_set" @($Distro, $VhdSizeGB)) }
                else { Write-Warn (Msg "vhd_ko" @($Distro, $VhdSizeGB, $resizeExit)); Write-Warn $resizeOutput }
            }
            else {
                Write-Warn (Msg "vhd_later" @($Distro))
            }
        }
    }
}
elseif ($DryRun) {
    Write-Info ("wsl --install -d $Distro " + ($installArguments -join " ")).Trim()
}
else {
    if (-not (Test-OnlineDistro -Name $Distro)) { Stop-Setup (Msg "distro_not_online" @($Distro)) }
    Write-Info (Msg "distro_installing" @($Distro))
    Write-Host "        [ !! ] " -ForegroundColor Black -BackgroundColor Yellow -NoNewline
    Write-Host " $(Msg 'distro_exit_hint')" -ForegroundColor Yellow
    Write-Host ""
    wsl.exe --install -d $Distro @vhdArguments
    if ($LASTEXITCODE -ne 0) { Stop-Setup (Msg "distro_install_failed" @($Distro, $LASTEXITCODE)) }
    if ($VhdSizeGB -gt 0) { Write-Ok (Msg "vhd_set" @($Distro, $VhdSizeGB)) }
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

    # Mirrored networking does not work everywhere (some VPNs, DNS filters, virtual machines): NAT is the way out.
    $online = Test-DistroNetwork -Name $Distro
    if ($online) {
        Write-Ok (Msg "network_ok" @($Distro))
    }
    else {
        $inUse = Read-IniValues -Text $(if (Test-Path -LiteralPath $wslConfigPath) { [IO.File]::ReadAllText($wslConfigPath) } else { "" })
        if ($inUse["wsl2.networkingmode"] -ieq "mirrored") {
            Write-Warn (Msg "network_mirrored_ko" @($Distro))
            if (Read-YesNo -Question (Msg "ask_network_nat") -Default $true) {
                Set-WslNetworking -Mode "nat"
                $online = Test-DistroNetwork -Name $Distro
                if ($online) {
                    Write-Warn (Msg "network_fallback")
                }
                else {
                    Set-WslNetworking -Mode "mirrored"
                    Write-Warn (Msg "network_fallback_ko")
                }
            }
        }
        if (-not $online) {
            $servers = @(wsl.exe -d $Distro -u root --exec sed -n "s/^nameserver //p" /etc/resolv.conf) -join ", "
            Write-Warn (Msg "network_ko" @($Distro, $servers))
        }
    }
}

# ---------------------------------------------------------------------------------------------
Write-Step 6 "step_stack"
$stackArguments = @("--yes")
if ($Shell) { $stackArguments += @("--shell", $Shell) }
if ($WslInitTimeout -gt 0) { $stackArguments += @("--wsl-init-timeout", $WslInitTimeout) }
if ($WslAppendWindowsPath) { $stackArguments += @("--wsl-append-windows-path", $WslAppendWindowsPath) }
if (Read-YesNo -Question (Msg "ask_stack" @($Distro))) {
    Write-Info (Msg "stack_info")
    if ($DryRun) {
        $dryFrom = if ($StackScript) { $StackScript } else { "$installHost/lamp" }
        Write-Info "$dryFrom -> bash lamp-lapp-stack.sh $($stackArguments -join ' ')"
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
Write-Step 7 "step_docker"
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
Write-Step 8 "step_shortcuts"
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
