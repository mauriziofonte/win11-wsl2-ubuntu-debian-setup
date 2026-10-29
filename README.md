# LAMP/LAPP Stack on Windows 11 with WSL2, Debian 13 or Ubuntu 24.04/26.04, native systemd services and VS Code

[![CI](https://github.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup/actions/workflows/ci.yml)

This project sets up a **LAMP/LAPP development stack** on Windows 11 (and Windows 10 1903+) inside **WSL2**, on **Debian 13** (recommended), **Ubuntu 24.04** or **Ubuntu 26.04**, with the stack running as _native systemd services_ instead of containers, and VS Code connected to it.

In a hurry? Skip to the [Automated Install](#automated-install).

## What is a LAMP/LAPP Stack?

`LAMP` stands for **L**inux, **A**pache, **M**ySQL/MariaDB and **P**HP; `LAPP` for **L**inux, **A**pache, **P**ostgreSQL and **P**HP. Both are long-standing open-source stacks for dynamic web applications.

## Why WSL2, and why native services instead of containers?

1. You keep Windows as your desktop, and you get a real Linux terminal and filesystem through **WSL2**.
2. The stack runs as **native systemd services** (MariaDB, PostgreSQL, Redis) and as per-user processes for the local sites (`gash hte`). When a client's production runs on a plain VM, a shared hosting or a server where containers are not an option, the development environment should resemble it as much as possible: many PHP versions side by side, switchable per site, on the same Apache and databases.
3. If you prefer Docker, you can have both: the Windows installer offers to install **Docker Desktop**, which uses the same WSL2 backend.

## What will the stack be?

> TL;DR: PHP 5.6 to **8.5** (CLI + FPM), Apache 2.4, **MariaDB 11.8 LTS**, **PostgreSQL 18**, Redis, Composer 2 and 1, Gash with `gash hte` for local sites, Node LTS via nvm, a WSL virtual machine sized for your PC, and Bash with Gash as your shell (or Bash with fzf/zoxide/starship, Zsh, Fish, or plain Bash).

1. PHP from [packages.sury.org](https://packages.sury.org/php/), on Debian and Ubuntu alike (it is absorbing `ppa:ondrej/php`, which an existing Ubuntu install may keep): every version from 5.6 to 8.5, with the usual extensions (intl, gd, imagick, mysql, pgsql, redis, memcached, xml, zip, ...)
2. Local sites with **[`gash hte`](https://github.com/mauriziofonte/gash/blob/main/docs/hte/README.md)**: Apache and PHP-FPM run as your user, each site has its own PHP version, HTTPS with a self-signed certificate, HTTP/2, and the names go into `/etc/hosts` automatically
3. **MariaDB 11.8 LTS** (maintained upstream until June 2028; on Debian 13 and Ubuntu 26.04 it is the distribution's own package), tuned for development, with a `default` user for your applications
4. **PostgreSQL 18** from the official pgdg repository
5. On WSL: a `.wslconfig` sized for your PC (three profiles to choose from, NAT or mirrored networking, an optional cap on the virtual disk), systemd, `/tmp` on tmpfs, TRIM so that the virtual disk gives space back to Windows, no failing tty units
6. Your shell: **Bash with [Gash](https://github.com/mauriziofonte/gash)** (recommended: PHP and Composer per version, WSL and Windows helpers, a git-aware prompt), or **Bash with fzf, zoxide and starship**, or a **minimal Zsh** (autosuggestions and syntax highlighting, no framework), or **Fish**, or the plain Bash of the distribution. See [Your shell](/docs/en/SETUP-EN.md#6-your-shell-gash-or-an-alternative)

## Checked by CI, at every change and every week

The guide states facts, and CI checks them on real systems instead of trusting them ([what exactly is checked](/tests/README.md)):

* **Real WSL2 on Windows**: the Windows setup runs end to end on Debian 13, Ubuntu 24.04 and Ubuntu 26.04 inside WSL2 on a Windows runner, each with other options: the defaults; a `.wslconfig` of your own, a disk limit and Fish; mirrored networking and Bash with fzf/zoxide/starship. Then `.wslconfig` must hold exactly what was asked, the virtual machine must have that RAM, those processors, that swap, that network mode and that disk size, every component is checked against the guide, the guide's "first local site" commands run as written, Windows opens `https://shop.test/`, the distribution restarts and everything comes back, and a second run changes nothing.
* **The Windows setup on its own**: the three profiles match the tables of the guides, the `.wslconfig` merge keeps your own lines, every invalid option is refused before anything changes, and a dry run shows every step, in Windows PowerShell 5.1 and PowerShell 7.
* **Plain machines**: the stack installer runs in containers with systemd, with other options (each `--shell`, `--no-gash`, a subset of PHP versions, high ports, the `/etc/wsl.conf` options), after a port conflict from another network namespace (the situation of two WSL distributions), and the manual steps of the guide run as written.
* **The documents themselves**: the options tables match the installers, the English and Italian guides match command for command, every link and anchor resolves, and every `gash` command the guide shows exists, with those flags, in the current Gash.

## Installation

### Automated Install

Open **PowerShell** (no need to run it as Administrator) and run:

```powershell
irm https://wsl.mauriziofonte.it | iex
```

A new window opens: confirm the administrator (UAC) prompt, and the setup guides you through eight steps, in English or Italian (it follows the Windows display language). It asks its questions first, then works on its own:

```text
  ================================================================
   WSL2 + LAMP/LAPP development environment
   Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 on Windows  -  v2.1.0
  ================================================================

  [1/8] Checking this computer
        [ OK ] Running as Administrator
        [ OK ] Internet connection OK
        [ OK ] Windows build 26300
        [ OK ] Distribution: Debian
        [ OK ] Shell: gash

        [ .. ] This PC: 32 GB of RAM, 16 logical processors

        How much of this PC may the WSL virtual machine use?
          1) Light        8 GB of RAM, 4 processors, 4 GB of swap
          2) Balanced     16 GB of RAM, 8 processors, 8 GB of swap
          3) Performance  22 GB of RAM, 12 processors, 8 GB of swap
          Windows always keeps at least 6 GB of RAM and 2 processors for itself.
        Your choice [1-3, Enter = 2]:
        [ OK ] Virtual machine: Balanced (16 GB of RAM, 8 processors, 8 GB of swap)
  ...
```

| Step | What happens |
|---|---|
| 1. Checking this computer | Administrator rights, internet, Windows 11 (`-SkipWindowsVersionCheck` for Windows 10 1903+), every option checked. Then the questions: the distribution, your shell, and the [WSL settings](/docs/en/SETUP-EN.md#2-configure-wsl-on-the-windows-side): a resource profile computed from this PC, NAT or mirrored networking (each explained), WSLg, an optional disk limit |
| 2. Windows Subsystem for Linux | `wsl --install --no-distribution`. Windows restarts **only if it has to**; the setup then resumes by itself at your next login (a one-shot `RunOnce` entry, removed by Windows) |
| 3. Updating WSL | `wsl --update`, WSL 2.0 or later required |
| 4. WSL settings | Writes `%UserProfile%\.wslconfig`. An existing file keeps every line the setup does not set: you see the changes first, and a backup copy is kept. WSL restarts to use them (you are asked if a distribution is running) |
| 5. Linux distribution | `wsl --install -d <distro> --web-download` (the image comes from the distribution's site, not the Microsoft Store): you choose your Linux username and password, then type `exit`. A distribution that is already installed is kept as it is (only its disk limit changes, if you set one). If you have other distributions, you are asked before the new one becomes the default |
| 6. LAMP/LAPP stack | Runs the [stack installer](#the-stack-installer-also-runs-on-its-own) inside the distribution (it asks once for your sudo password), with the shell you chose, then restarts the distribution to apply its WSL settings |
| 7. Docker Desktop | Optional, default **no** |
| 8. Desktop shortcuts | A Linux terminal and the Linux home folder |

At the end you get a summary with the next commands. Every run writes a log to `%LOCALAPPDATA%\WSL2Setup\setup-<date>.log`. If something stops, fix the cause and run the same command again: completed steps are detected and skipped.

Options, with this form of the command:

```powershell
& ([scriptblock]::Create((irm https://wsl.mauriziofonte.it))) -Distro Ubuntu-26.04
```

| Option | Effect |
|---|---|
| `-Distro Debian\|Ubuntu-24.04\|Ubuntu-26.04` | Skip the distribution question |
| `-Shell gash\|bash-plus\|zsh\|fish\|bash` | Your shell in Linux: Bash with Gash (default), Bash with fzf/zoxide/starship, a minimal Zsh, Fish, or plain Bash |
| `-VmProfile Light\|Balanced\|Performance\|Current` | The resources of the WSL virtual machine: one of the [three profiles](/docs/en/SETUP-EN.md#2-configure-wsl-on-the-windows-side) computed from this PC, or `Current`, the values already in `.wslconfig` |
| `-WslMemoryGB N`, `-WslProcessors N`, `-WslSwapGB N` | RAM, logical processors and swap of the virtual machine, each one over the profile (`-WslSwapGB 0`: no swap) |
| `-WslNetworking nat\|mirrored` | The network mode (mirrored needs Windows 11 22H2) |
| `-WslGui true\|false` | WSLg, the Linux applications with a window |
| `-VhdSizeGB N` | The maximum size of the distribution's virtual disk, in GB (`0`: no limit) |
| `-WslInitTimeout MS` | `/etc/wsl.conf` `[boot] initTimeout`: how long WSL waits for systemd (default 30000) |
| `-WslAppendWindowsPath true\|false` | `/etc/wsl.conf` `[interop] appendWindowsPath`: the Windows folders on the Linux `PATH` |
| `-Unattended` | Answer every question with its default and never wait for Enter (restart Windows yourself if WSL needed it); you still choose the Linux user of a new distribution. On a PC that already has a `.wslconfig`, only what the options name changes in it |
| `-DryRun` | Show every step without changing anything |
| `-Force` | Forget the state of an interrupted run and start over (installed distributions are kept) |
| `-SkipWindowsVersionCheck` | Allow Windows 10 1903 or later |

Every option is checked before anything changes: a wrong value stops the setup with the list of the problems. An option given explicitly wins over the profile and over the value already in `.wslconfig`; without options, `-Unattended` picks the Balanced profile, NAT, no WSLg and no disk limit on a PC that has no `.wslconfig` yet, and leaves an existing one alone. For example, a light machine on mirrored networking with a 128 GB disk, without questions:

```powershell
& ([scriptblock]::Create((irm https://wsl.mauriziofonte.it))) -Unattended -VmProfile Light -WslNetworking mirrored -VhdSizeGB 128
```

Run directly, `win11.ps1` also takes `-StackScript <path>`: it runs that copy of `lamp-lapp-stack.sh` (one you reviewed) instead of downloading the released one.

`wsl.mauriziofonte.it` redirects to the files of the latest [release](https://github.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup/releases) of this repository (or of `main`, before the first release), so the whole chain runs one consistent version.

#### The stack installer also runs on its own

On an existing **Debian 13**, **Ubuntu 24.04** or **Ubuntu 26.04**, under WSL2 or on a plain machine, run as your normal user:

```bash
curl -fsSL https://wsl.mauriziofonte.it/lamp | bash
```

The Debian image of WSL ships without `curl`: install it first with `sudo apt-get update && sudo apt-get install -y curl` (the Windows setup above does not need it, it downloads the script on the Windows side).

It accepts options after `bash -s --` (`--yes`, `--php "8.4 7.4"`, `--pg 18`, `--shell fish`, `--no-gash`, `--hte-ports high`, ...: see `--help` and [the options table](/docs/en/SETUP-EN.md#4-run-the-stack-installer)). It **converges**: running it again changes only what differs, so after a failure you fix the cause and run it again. On a cloud VM, remember that the stack is configured for **local development**: everything listens on 127.0.0.1 only and nothing is hardened for the internet.

> All WSL2 distributions share one network: if another distribution already runs a LAMP stack, stop its services first. The installer detects the conflict and tells you.

### Manual Install

Step-by-step instructions, which also explain what the installers change:

* [Manual installation instructions in **English**](/docs/en/SETUP-EN.md)
* [Manual installation instructions in **Italian**](/docs/it/SETUP-IT.md)

## Uninstall

```powershell
wsl --unregister Debian       # or Ubuntu-24.04, Ubuntu-26.04
```

This deletes the distribution and everything inside it. If the automated installer was interrupted, also run, in an administrator PowerShell:

```powershell
Remove-Item -Path "HKCU:\Software\WSL2Setup" -Force -ErrorAction SilentlyContinue | Out-Null
```

## Keeping the virtual disk small

The Windows setup sets `sparseVhd=true` in `%UserProfile%\.wslconfig` (see the [manual](/docs/en/SETUP-EN.md#2-configure-wsl-on-the-windows-side)) before it installs the distribution: together with the TRIM timer enabled by the stack installer, the space you free inside Linux goes back to Windows. An existing distribution can be converted with `wsl --manage <Distro> --set-sparse true`. To stop the disk from growing without bounds, give it a limit: the setup asks, or `-VhdSizeGB`.

## Maintainers

The sole maintainer is @mauriziofonte. More maintainers are welcome.

## License

Released under MIT License. Refer to the [LICENSE](/LICENSE) file.

## Disclaimer

The information provided in this repository is for general informational purposes only. All information is provided in good faith, however I make no representation or warranty of any kind, express or implied, regarding the accuracy, adequacy, validity, reliability, availability, or completeness of any information on this repository.

UNDER NO CIRCUMSTANCE SHALL I HAVE ANY LIABILITY TO YOU FOR ANY LOSS OR DAMAGE OF ANY KIND INCURRED AS A RESULT OF THE USE OF THE INFORMATIONS, GUIDES, HOW-TOS, AND SCRIPTS PROVIDED IN THIS REPOSITORY OR RELIANCE ON ANY INFORMATION PROVIDED ON THIS REPOSITORY. YOUR USE OF THIS WORK AND YOUR RELIANCE ON ANY INFORMATION IS SOLELY AT YOUR OWN RISK.

This repository contains links to other websites or content belonging to or originating from third parties or links to websites and features in banners or other advertising. Such external links are not investigated, monitored, or checked for accuracy, adequacy, validity, reliability, availability, or completeness.
