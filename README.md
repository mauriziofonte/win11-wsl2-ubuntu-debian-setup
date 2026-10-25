# LAMP/LAPP Stack on Windows 11 with WSL2, Debian 13 or Ubuntu 24.04/26.04, native systemd services and VS Code

This project sets up a **LAMP/LAPP development stack** on Windows 11 (and Windows 10 1903+) inside **WSL2**, on **Debian 13** (recommended), **Ubuntu 24.04** or **Ubuntu 26.04**, with the stack running as _native systemd services_ instead of containers, and VS Code connected to it.

In a hurry? Skip to the [Automated Install](#automated-install).

## What is a LAMP/LAPP Stack?

`LAMP` stands for **L**inux, **A**pache, **M**ySQL/MariaDB and **P**HP; `LAPP` for **L**inux, **A**pache, **P**ostgreSQL and **P**HP. Both are long-standing open-source stacks for dynamic web applications.

## Why WSL2, and why native services instead of containers?

1. You keep Windows as your desktop, and you get a real Linux terminal and filesystem through **WSL2**.
2. The stack runs as **native systemd services** (MariaDB, PostgreSQL, Redis) and as per-user processes for the local sites (`gash hte`). When a client's production runs on a plain VM, a shared hosting or a server where containers are not an option, the development environment should resemble it as much as possible: many PHP versions side by side, switchable per site, on the same Apache and databases.
3. If you prefer Docker, you can have both: the Windows installer offers to install **Docker Desktop**, which uses the same WSL2 backend.

## What will the stack be?

> TL;DR: PHP 5.6 to **8.5** (CLI + FPM), Apache 2.4, **MariaDB 11.8 LTS**, **PostgreSQL 18**, Redis, Composer 2 and 1, Gash with `gash hte` for local sites, Node LTS via nvm.

1. PHP from [packages.sury.org](https://packages.sury.org/php/), on Debian and Ubuntu alike (it is absorbing `ppa:ondrej/php`, which an existing Ubuntu install may keep): every version from 5.6 to 8.5, with the usual extensions (intl, gd, imagick, mysql, pgsql, redis, memcached, xml, zip, ...)
2. Local sites with **[`gash hte`](https://github.com/mauriziofonte/gash/blob/main/docs/hte.md)**: Apache and PHP-FPM run as your user, each site has its own PHP version, HTTPS with a self-signed certificate, HTTP/2, and the names go into `/etc/hosts` automatically
3. **MariaDB 11.8 LTS** (EOL 13 February 2030), tuned for development, with a `default` user for your applications
4. **PostgreSQL 18** from the official pgdg repository
5. On WSL: systemd, `/tmp` on tmpfs, TRIM so that the virtual disk gives space back to Windows, no failing tty units

## Installation

### Automated Install

Open **PowerShell** (no need to run it as Administrator) and run:

```powershell
irm https://wsl.mauriziofonte.it | iex
```

A new window opens: confirm the administrator (UAC) prompt, and the setup guides you through seven steps, in English or Italian (it follows the Windows display language):

```text
  ================================================================
   WSL2 + LAMP/LAPP development environment
   Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 on Windows  -  v2.0.0
  ================================================================

  [1/7] Checking this computer
        [ OK ] Running as Administrator
        [ OK ] Internet connection OK
        [ OK ] Windows build 26300

        Which Linux distribution do you want to install?
          1) Debian 13        (recommended)
          2) Ubuntu 24.04 LTS
          3) Ubuntu 26.04 LTS
        Your choice [1-3, Enter = 1]:
        [ OK ] Distribution: Debian

  [2/7] Windows Subsystem for Linux
        [ OK ] WSL is already installed (3.0.3)
  ...
```

| Step | What happens |
|---|---|
| 1. Checking this computer | Administrator rights, internet, Windows 11 (`-SkipWindowsVersionCheck` for Windows 10 1903+), choice of the distribution |
| 2. Windows Subsystem for Linux | `wsl --install --no-distribution`. Windows restarts **only if it has to**; the setup then resumes by itself at your next login (a one-shot `RunOnce` entry, removed by Windows) |
| 3. Updating WSL | `wsl --update`, WSL 2.0 or later required |
| 4. Linux distribution | `wsl --install -d <distro>`: you choose your Linux username and password, then type `exit`. A distribution that is already installed is kept as it is. If you have other distributions, you are asked before the new one becomes the default |
| 5. LAMP/LAPP stack | Runs the [stack installer](#the-stack-installer-also-runs-on-its-own) inside the distribution (it asks once for your sudo password), then restarts the distribution to apply its WSL settings |
| 6. Docker Desktop | Optional, default **no** |
| 7. Desktop shortcuts | A Linux terminal and the Linux home folder |

At the end you get a summary with the next commands. Every run writes a log to `%LOCALAPPDATA%\WSL2Setup\setup-<date>.log`. If something stops, fix the cause and run the same command again: completed steps are detected and skipped.

Options, with this form of the command:

```powershell
& ([scriptblock]::Create((irm https://wsl.mauriziofonte.it))) -Distro Ubuntu-26.04
```

| Option | Effect |
|---|---|
| `-Distro Debian\|Ubuntu-24.04\|Ubuntu-26.04` | Skip the distribution question |
| `-DryRun` | Show every step without changing anything |
| `-Force` | Forget the state of an interrupted run and start over (installed distributions are kept) |
| `-SkipWindowsVersionCheck` | Allow Windows 10 1903 or later |

`wsl.mauriziofonte.it` redirects to the files of the latest [release](https://github.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup/releases) of this repository (or of `main`, before the first release), so the whole chain runs one consistent version.

#### The stack installer also runs on its own

On an existing **Debian 13**, **Ubuntu 24.04** or **Ubuntu 26.04**, under WSL2 or on a plain machine, run as your normal user:

```bash
curl -fsSL https://wsl.mauriziofonte.it/lamp | bash
```

The Debian image of WSL ships without `curl`: install it first with `sudo apt-get update && sudo apt-get install -y curl` (the Windows setup above does not need it, it downloads the script on the Windows side).

It accepts options after `bash -s --` (`--yes`, `--php "8.4 7.4"`, `--pg 18`, `--no-gash`, `--hte-ports high`, ...: see `--help`). It **converges**: running it again changes only what differs, so after a failure you fix the cause and run it again. On a cloud VM, remember that the stack is configured for **local development**: everything listens on 127.0.0.1 only and nothing is hardened for the internet.

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

Set `sparseVhd=true` in `%UserProfile%\.wslconfig` (see the [manual](/docs/en/SETUP-EN.md#2-configure-wsl-on-the-windows-side-optional-recommended)): together with the TRIM timer enabled by the installer, the space you free inside Linux goes back to Windows. An existing distribution can be converted with `wsl --manage <Distro> --set-sparse true`.

## Maintainers

The sole maintainer is @mauriziofonte. More maintainers are welcome.

## License

Released under MIT License. Refer to the [LICENSE](/LICENSE) file.

## Disclaimer

The information provided in this repository is for general informational purposes only. All information is provided in good faith, however I make no representation or warranty of any kind, express or implied, regarding the accuracy, adequacy, validity, reliability, availability, or completeness of any information on this repository.

UNDER NO CIRCUMSTANCE SHALL I HAVE ANY LIABILITY TO YOU FOR ANY LOSS OR DAMAGE OF ANY KIND INCURRED AS A RESULT OF THE USE OF THE INFORMATIONS, GUIDES, HOW-TOS, AND SCRIPTS PROVIDED IN THIS REPOSITORY OR RELIANCE ON ANY INFORMATION PROVIDED ON THIS REPOSITORY. YOUR USE OF THIS WORK AND YOUR RELIANCE ON ANY INFORMATION IS SOLELY AT YOUR OWN RISK.

This repository contains links to other websites or content belonging to or originating from third parties or links to websites and features in banners or other advertising. Such external links are not investigated, monitored, or checked for accuracy, adequacy, validity, reliability, availability, or completeness.
