# Manual LAMP+LAPP Stack Setup on Windows 11 with WSL2, Debian 13 or Ubuntu 24.04/26.04, Native Services and VS Code

> Last updated at: _2026-10-29_. Targets: **Debian 13 (trixie)** (recommended), **Ubuntu 24.04 (noble)** and **Ubuntu 26.04 (resolute)**.
>
> Checked by CI: the installers run on a real WSL2 and on plain machines at every change and every week, and the results are compared with what this page says. See [what CI verifies](/tests/README.md).

This guide installs WSL2 and a Linux distribution on Windows 11 without the Microsoft Store, then builds a multi-PHP **LAMP+LAPP** stack running as native _systemd_ services, and connects Visual Studio Code to it. Every step below is what the automated installers ([win11.ps1](/install/win11.ps1) and [lamp-lapp-stack.sh](/install/lamp-lapp-stack.sh)) do, so you can follow it by hand, check what the scripts change, or repair a single step.

## System Requirements

1. **Windows 11**, kept up to date through Windows Update (Windows 10 1903 or later works too)
2. 16 GB of RAM (32 GB recommended if you run many PHP versions and databases together)
3. At least 50 GB free on C:\\ for the Linux virtual disk
4. An SSD, better if NVMe, as the main Windows disk
5. Basic knowledge of the Linux terminal (`cd`, `cp`, `mv`, `sudo`, `nano`, ...)
6. A **password-protected** PC with **BitLocker** and **TPM 2.0**: your Linux home holds source code, databases and keys. This matters most if you handle data on behalf of others.

What you get:

| Component | Version | Source |
|---|---|---|
| PHP (CLI + FPM) | 5.6, 7.0, 7.1, 7.2, 7.3, 7.4, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5 | [sury](https://packages.sury.org/php/) |
| Apache | 2.4 | distribution |
| MariaDB | 11.8 LTS | Debian 13 and Ubuntu 26.04 themselves; [mariadb.org](https://mariadb.org/download/) on Ubuntu 24.04 (which ships 10.11) |
| PostgreSQL | 18 | [pgdg](https://wiki.postgresql.org/wiki/Apt) |
| Redis | distribution | distribution |
| Composer | 2 and 1 | [getcomposer.org](https://getcomposer.org/download/), checksum verified |
| Local sites | `gash hte` | [Gash](https://github.com/mauriziofonte/gash) |
| Shell | Bash with Gash (default), Bash with fzf/zoxide/starship, Zsh, Fish, or plain Bash | see [section 6](#6-your-shell-gash-or-an-alternative) |
| Node | LTS via nvm | [nvm](https://github.com/nvm-sh/nvm) |

MariaDB 11.8 is a long-term release: upstream maintains it until June 2028. On Debian 13 and Ubuntu 26.04 it is the distribution's own package, so it gets the distribution's security updates for as long as the distribution is supported.

Local sites are served by **`gash hte`**: Apache and one PHP-FPM master per PHP version in use, running as **your user** (no root process), with HTTPS (self-signed, ECDSA, 10 years), HTTP/2 and a PHP version per site. It replaces the system Apache configuration and the `hte-cli` tool used by the previous versions of this guide.

## 1. Install WSL

Open **PowerShell as Administrator** and run:

```powershell
wsl --install --no-distribution
```

This enables the _Windows Subsystem for Linux_ and the _Virtual Machine Platform_ and installs the WSL package. **Restart the computer**, then, again in an administrator PowerShell:

```powershell
wsl --update
wsl --set-default-version 2
wsl --version
```

`wsl --version` must report WSL **2.0 or later**.

## 2. Configure WSL on the Windows side

WSL reads the settings of its virtual machine from `%UserProfile%\.wslconfig`. Without that file WSL may take half of your RAM, and the virtual disk of each distribution can grow up to 1 TB without ever giving space back. The Windows setup writes the file for you (its step 4) from the answers to the questions below. If you already have a `.wslconfig`, it shows what would change and asks first; every line it does not set stays as it is, and a backup copy is kept next to the file.

**Resources: three profiles computed from your PC.** Light gives the virtual machine a quarter of the RAM and of the logical processors, Balanced (the default) half of them, Performance 70% of the RAM and 75% of the processors. Windows always keeps at least 6 GB of RAM (half of it on a PC with less than 12 GB) and 2 logical processors. The swap file is half the RAM of the virtual machine, from 1 to 8 GB. For example:

<!-- ci:profiles -->
| This PC: RAM installed (usable), logical processors | Light | Balanced | Performance |
|---|---|---|---|
| 8 GB (7.6), 4 | 2 GB, 2 processors, 1 GB swap | 4 GB, 2 processors, 2 GB swap | 4 GB, 2 processors, 2 GB swap |
| 16 GB (15.6), 8 | 4 GB, 2 processors, 2 GB swap | 8 GB, 4 processors, 4 GB swap | 9 GB, 6 processors, 4 GB swap |
| 32 GB (31.4), 16 | 8 GB, 4 processors, 4 GB swap | 16 GB, 8 processors, 8 GB swap | 22 GB, 12 processors, 8 GB swap |
| 64 GB (63.4), 32 | 16 GB, 8 processors, 8 GB swap | 32 GB, 16 processors, 8 GB swap | 44 GB, 24 processors, 8 GB swap |

The usable RAM is what Windows can use, a little less than what is installed. If your `.wslconfig` already sizes the virtual machine, a fourth choice keeps those values, and it is the default.

**Networking: NAT or mirrored.** The setup explains both and asks; with an existing `.wslconfig` it proposes the mode already in use.

| Mode | What it means | Choose it when |
|---|---|---|
| NAT (the WSL default) | Linux has its own private network behind Windows. Windows reaches the Linux servers through `localhost`; other computers on your network do not see them | You develop on this PC only. It is the default of the setup too, and the choice of `-Unattended` |
| Mirrored | Linux shares the network interfaces of Windows: `localhost` works in both directions (Linux reaches a server running on Windows at `127.0.0.1`), IPv6 works, VPNs work better, and other computers on your network can reach the Linux servers if the Windows firewall lets them through. A port that Windows already uses cannot be used in Linux | You test from a phone or another PC, work behind a VPN, or need IPv6. It needs Windows 11 22H2 or later |

With mirrored networking the setup also writes `dnsTunneling`, `autoProxy` and `firewall` as `true` (their defaults), so the file says in full what is in force. Mirrored networking does not work on every PC (some VPNs, DNS filters and virtual machines leave Linux without DNS): once the distribution is installed, the setup checks that it resolves `github.com`, and if it does not under mirrored networking, it offers to switch `.wslconfig` to NAT (unattended, it switches) and keeps NAT only if that works.

**WSLg.** The setup asks whether you run Linux applications with a window; if not, `guiApplications=false` saves the memory of the WSLg system distribution.

**Disk limit.** The setup asks whether to limit the space the distribution can take, and proposes about half of the free space on its drive, rounded down to 512, 256, 128 or 64 GB (you can type another size). The limit applies to a new distribution through `wsl --install --vhd-size`, to one you already have through `wsl --manage <distro> --resize` (never below what it already uses), and to the distributions you add later through `defaultVhdSize`. Both commands need WSL 2.5 or later. When a limited disk fills up, raise the limit:

```powershell
wsl --shutdown
wsl --manage Debian --resize 256GB
```

**Always set**: `maxCrashDumpCount=3` (WSL keeps 10 crash dumps by default), `sparseVhd=true` (a new virtual disk gives back to Windows the space you free inside Linux; the setup writes it before it creates the distribution) and `autoMemoryReclaim=dropCache` (memory that Linux only uses as cache goes back to Windows when the virtual machine is idle).

The file the setup writes for Balanced on a 32 GB PC with 16 logical processors, NAT, no WSLg and no disk limit; to do it by hand, write it yourself:

<!-- ci:wslconfig -->
```ini
[wsl2]
# RAM of the WSL virtual machine
memory=16GB
# Logical processors of the WSL virtual machine
processors=8
# Swap file of the WSL virtual machine, on the Windows disk
swap=8GB
# nat: a private network behind Windows; mirrored: the network interfaces of Windows
networkingMode=nat
# WSLg: Linux applications with a window
guiApplications=false
# Crash dumps kept in %Temp%\wsl-crashes
maxCrashDumpCount=3

[experimental]
# New virtual disks are sparse: space freed inside Linux goes back to Windows
sparseVhd=true
# Give cached memory back to Windows when the VM is idle
autoMemoryReclaim=dropCache
```

The settings apply at the next WSL start: run `wsl --shutdown` after editing the file (the setup does it for you, and asks first if a distribution is running). With Gash installed, `gash wsl config` shows every setting in force and where it comes from (section 7).

## 3. Install the distribution

```powershell
wsl --list --online
wsl --install -d Debian          # or: Ubuntu-24.04, Ubuntu-26.04
```

When asked, choose a Linux **username** and **password**: the password is your `sudo` password. When you get the Linux prompt, you are done.

> All WSL2 distributions share **one network**. If you already run a LAMP stack in another distribution, its ports (80, 443, 3306, 5432, 6379) are taken for the new one too: stop those services there first (`sudo systemctl stop apache2 mariadb postgresql redis-server`). The installer checks this and stops with a clear message.

## 4. Run the stack installer

Inside the distribution, as your normal user. The Debian image of WSL ships without `curl`, so on Debian install it first: `sudo apt-get update && sudo apt-get install -y curl`.

```bash
curl -fsSL https://wsl.mauriziofonte.it/lamp | bash
```

Options go after `bash -s --`, for example `... | bash -s -- --yes --php "8.4 8.3 7.4" --shell fish`:

| Option | Effect |
|---|---|
| `-y`, `--yes` | Never prompt, take the defaults |
| `--php "X.Y ..."` | PHP versions to install (default: all, 5.6 to 8.5) |
| `--pg N` | PostgreSQL major version (default: 18) |
| `--shell gash\|bash-plus\|zsh\|fish\|bash` | Your interactive shell: Bash with Gash (default), Bash with fzf/zoxide/starship, a minimal Zsh, Fish, or the distribution's Bash unchanged (see [section 6](#6-your-shell-gash-or-an-alternative)). Asked when not given, on a terminal without `--yes` |
| `--no-gash` | Do not install Gash (and so no `gash hte`); implies `--shell bash` |
| `--no-hte` | Install Gash but do not set up `gash hte` |
| `--hte-ports standard\|high` | Ports for local sites: 80/443 (default) or high ports (8080/8443) |
| `--no-node` | Do not install nvm and Node |
| `--wsl`, `--no-wsl` | Force or skip the WSL tuning (default: detected) |
| `--tmp-size SIZE` | Size cap of `/tmp` on WSL, e.g. `6G` or `25%` (default: `25%`) |
| `--wsl-init-timeout MS` | How long WSL waits for systemd to start, in milliseconds, 1000 to 600000 (default: 30000, or the value already in `/etc/wsl.conf`) |
| `--wsl-append-windows-path true\|false` | Whether WSL puts the Windows folders on the Linux `PATH` (default: left as it is, which means `true`) |

The installer **converges**: each step checks the current state and changes only what differs. If it stops (network error, a port in use), fix the cause and **run it again**. A full log of every run is written to `~/.local/state/lamp-lapp-stack/`.

At the end, if it says that WSL settings changed, run `wsl --terminate Debian` (or `Ubuntu-24.04`, `Ubuntu-26.04`) from PowerShell and open the terminal again.

The sections below describe what each step does.

### 4.1 WSL tuning

Applied only on WSL:

| Change | Why |
|---|---|
| `/etc/wsl.conf`: `[boot] systemd=true` | The services run as systemd units |
| `/etc/wsl.conf`: `[automount] mountFsTab=false` | WSL would run `mount -a` before `/mnt/c` exists; systemd mounts `/etc/fstab` itself |
| `/etc/wsl.conf`: `[user] default=<you>` | The terminal opens as your user |
| `/etc/wsl.conf`: `[boot] initTimeout=30000` | WSL waits 10 seconds for systemd by default: a slow first boot (a file system check, a long cleanup of `/tmp`) then loses the session. A value already in the file is kept; `--wsl-init-timeout` sets another one |
| `/etc/wsl.conf`: `[interop] appendWindowsPath`, only with `--wsl-append-windows-path` | `false` keeps the Windows folders off the Linux `PATH`: command lookup and completion get faster, and Linux tools never pick a Windows program by mistake. Windows programs then need their full path (`/mnt/c/Windows/explorer.exe`); Gash calls them by full path, so `gash win` keeps working |
| `/tmp` on tmpfs, capped by `--tmp-size` | A disk `/tmp` is emptied at every boot, which slows WSL boot down; keep large temporary files in `/var/tmp` |
| `fstrim.timer` enabled, with a drop-in that clears `ConditionVirtualization` | systemd sees WSL as a container and would never run TRIM: without it a sparse virtual disk never gives space back |
| `getty@tty1.service` masked | WSL has no tty1: the unit only fails and marks the system "degraded" |

The installer only sets these keys in `/etc/wsl.conf` and leaves the rest of the file as it is. It does **not** change DNS settings.

### 4.2 Repositories

Debian 13 and Ubuntu (the codename is `trixie` on Debian 13, `noble` on Ubuntu 24.04, `resolute` on Ubuntu 26.04):

<!-- ci:run repositories -->
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl lsb-release postgresql-common
curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
sudo dpkg -i /tmp/debsuryorg-archive-keyring.deb
echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
sudo apt-get update
```

Ubuntu 24.04 ships MariaDB 10.11, so it also needs the mariadb.org repository:

<!-- ci:run mariadb-repository -->
```bash
curl -fsSL https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version=mariadb-11.8 --skip-maxscale --skip-tools
sudo apt-get update
```

The `ppa:ondrej/php` used by the previous versions of this guide is being merged into packages.sury.org, and Ubuntu 26.04 is served only there. If your Ubuntu already uses the PPA, the installer keeps it and does not add sury, so the same packages never come from two sources.

### 4.3 Packages

For every PHP version `X.Y` the installer adds `phpX.Y-` + `cli fpm bcmath bz2 curl gd gmp igbinary imagick imap intl mbstring mcrypt memcached msgpack mysql opcache pgsql readline redis soap sqlite3 xml xsl zip` (PHP 8.5 has opcache built in). By hand, for PHP 8.5 and 8.4:

<!-- ci:run php-packages -->
```bash
sudo apt-get install -y php8.5-{cli,fpm,bcmath,bz2,curl,gd,gmp,igbinary,imagick,imap,intl,mbstring,mcrypt,memcached,msgpack,mysql,pgsql,readline,redis,soap,sqlite3,xml,xsl,zip}
sudo apt-get install -y php8.4-{cli,fpm,bcmath,bz2,curl,gd,gmp,igbinary,imagick,imap,intl,mbstring,mcrypt,memcached,msgpack,mysql,opcache,pgsql,readline,redis,soap,sqlite3,xml,xsl,zip}
```

Then the servers:

<!-- ci:run stack-packages -->
```bash
sudo apt-get install -y apache2 mariadb-server mariadb-client postgresql-18 postgresql-client-18 redis-server
sudo update-alternatives --set php /usr/bin/php8.5
sudo systemctl enable --now redis-server mariadb postgresql
```

The newest installed PHP becomes the default `php`.

### 4.4 MariaDB

The installer writes `/etc/mysql/mariadb.conf.d/99-custom.cnf` (development tuning: `utf8mb4` with `utf8mb4_unicode_ci`, 1 GB InnoDB buffer pool, no binary log, `NO_ENGINE_SUBSTITUTION`, listen on 127.0.0.1 only). Put your own overrides in a file that sorts after it, such as `99-zz-local.cnf`: re-running the installer rewrites `99-custom.cnf`.

| Account | Login | Password |
|---|---|---|
| `root` | `sudo mariadb` (unix socket) | none |
| `default` (all privileges, for your applications) | `mariadb -u default -p`, or 127.0.0.1:3306 | in `~/.mysql-pass` |

Anonymous users and the `test` database are removed.

### 4.5 PostgreSQL

| Role | Login | Password |
|---|---|---|
| `postgres` | `sudo -u postgres psql` | none (peer) |
| your username (superuser, with its own database) | `psql` | none (peer) |
| `default` (superuser, owns `defaultdb`) | `psql -h 127.0.0.1 -U default defaultdb` | in `~/.pgsql-pass` |

`default` is a reserved word in SQL: always quote it (`"default"`) in your own statements. PostgreSQL listens on localhost only.

### 4.6 Composer

`composer` (2.x) and `composer1` (1.x, for legacy projects) are downloaded to `/usr/local/bin` and checked against the published SHA-256. Composer 1 does not support recent PHP versions (with PHP 8.4+ it prints deprecation notices): run it with an old PHP, e.g. `1composer72`, the Gash alias for `php7.2 /usr/local/bin/composer1`.

### 4.7 Gash and `gash hte`

[Gash](https://github.com/mauriziofonte/gash) is a Bash toolkit: a prompt, helpers for files, git, databases, PHP versions, WSL and Windows, and the `gash hte` local-sites manager. The installer runs the [Gash installer](https://github.com/mauriziofonte/gash/blob/main/docs/install.md), which checks the SHA-256 of the Gash binary against the hash its release pins, then:

```bash
gash hte install --yes --ports standard
```

This uses `sudo` once to install a small helper for `/etc/hosts`, allow your user to bind ports 80 and 443 (`net.ipv4.ip_unprivileged_port_start = 80`), stop and disable the system Apache, and enable a systemd **user** unit (`gash-hte.service`) that starts the stack at boot. Since `gash hte` runs its own Apache and PHP-FPM masters, the installer then disables the system `phpX.Y-fpm` services, and the system Apache too when you chose the high ports (there `gash hte` leaves it alone): they would only use memory (about 70 MB per PHP version).

With `--shell gash` (the default), interactive Bash shells load Gash, which also defines `php85` ... `php56`, `composer85` ... `composer56`, `1composer72` ... `1composer56` and `composer-self-update`. With any other `--shell`, Gash leaves your shell alone and only the `gash` command is installed (in `~/.local/bin`), so `gash hte` works the same.

### 4.8 nvm and Node

nvm is installed from its official script, then `nvm install --lts`.

## 5. Your first local site

<!-- ci:run first-site -->
```bash
mkdir -p ~/sites/shop/public && echo '<?php echo "PHP ", PHP_VERSION, PHP_EOL;' > ~/sites/shop/public/index.php
cd ~/sites/shop
gash hte site create --domain shop.test --docroot public --php 8.4
curl -k https://shop.test/
```

The last command prints `PHP 8.4.x`. Inside Linux, `gash hte` keeps the names in `/etc/hosts`. Windows has its own hosts file: `gash hte hosts windows` prints the lines to add to `C:\Windows\System32\drivers\etc\hosts`, only for the names Windows cannot resolve yet (so it prints nothing once they are there). Add them as Administrator, or from the Linux terminal with `gash win fix hosts-add 127.0.0.1 shop.test`, which shows the command and asks for the Windows UAC prompt. Then open `https://shop.test/` in your Windows browser: WSL forwards Windows' localhost to Linux, and the browser warns about the self-signed certificate.

Useful commands: `gash hte site list`, `gash hte site modify --domain shop.test --php 7.4`, `gash hte site remove --domain shop.test --yes`, `gash hte doctor`. See the [gash hte guide](https://github.com/mauriziofonte/gash/blob/main/docs/hte/README.md).

## 6. Your shell: Gash, or an alternative

The installer sets up **Bash with Gash** unless you choose otherwise with `--shell` (or `-Shell` in the Windows setup). It is the recommended choice for this stack, because Gash is built around the same tasks:

* local HTTPS sites with `gash hte` (section 5);
* one command per PHP version (`php84`, `composer84`, `1composer72`) and `php_detect_version`, which reads the version a project wants from `composer.json` or `.target-php-version`;
* WSL and Windows from the Linux terminal (section 7);
* a git-aware prompt and helpers for disks, ports, databases, Docker and servers, each with `--help`;
* read-only `llm_*` functions with JSON output for AI coding agents.

Gash is open source, installs in your home directory, and its prompt, aliases and safety defaults can each be turned off. Its [documentation](https://github.com/mauriziofonte/gash/blob/main/docs/README.md) covers every area.

The alternatives:

| Choice | Installer option | What you get | What changes |
|---|---|---|---|
| **Bash with Gash** (recommended) | `--shell gash` (default) | Everything above | Gash adds one block to `~/.bashrc` |
| Bash with fzf, zoxide and starship | `--shell bash-plus` | Fuzzy search of the history and of files ([fzf](https://github.com/junegunn/fzf): `Ctrl-R`, `Ctrl-T`, `Alt-C`), `z <part of a path>` to jump to the directories you use ([zoxide](https://github.com/ajeetdsouza/zoxide)), the [starship](https://starship.rs/) prompt, 100000 lines of history shared by your terminals, case-insensitive completion | A block in `~/.bashrc` and a `~/.inputrc`. starship comes from the distribution where it is packaged; on Ubuntu 24.04, from a fixed release whose SHA-256 the installer checks |
| Zsh, minimal | `--shell zsh` | Zsh as your login shell, with autosuggestions and syntax highlighting, fzf, zoxide and starship, nvm and the `gash` command | A block in `~/.zshrc`. The plugins are the distribution's own packages, so `apt-get upgrade` updates them |
| Fish | `--shell fish` | [Fish](https://fishshell.com/) in every terminal: autosuggestions and highlighting built in, fzf, zoxide and starship, the `gash` command, and an `nvm` command that runs nvm through Bash | Bash stays your login shell, and an interactive Bash started by a terminal hands over to fish. Scripts, `bash -c`, VS Code and `sudo` keep running Bash. Fish is not a POSIX shell: run Bash snippets with `bash` |
| Plain Bash | `--shell bash` | The distribution's Bash as it is, with the `gash` command in `~/.local/bin` | Nothing in your shell files |
| No Gash at all | `--no-gash` | No `gash` command | No `gash hte`: serve your sites with the system Apache (enabled by its package) and edit its virtual hosts yourself |

With any choice but Gash, the Gash functions and aliases are not loaded: use `php8.4` and `gash run --runtime php:8.4 -- composer install` instead of `php84` and `composer84`. The `gash` command, and with it `gash hte`, works from every shell.

Why no Oh My Zsh? It loads a framework of hundreds of files at every new terminal and updates itself from the internet, while the two plugins that matter for daily work, autosuggestions and syntax highlighting, are packaged by Debian and Ubuntu and get their security updates with the rest of the system. Earlier versions of this setup installed Oh My Zsh: the installer leaves an existing `~/.oh-my-zsh` alone. To keep only the minimal setup, delete `~/.oh-my-zsh` and the Oh My Zsh lines of `~/.zshrc`.

Changing your mind is safe: run the installer again with another `--shell`. It sets the new shell up, removes the blocks it wrote for the previous one (and the Gash block of `~/.bashrc` when you leave Gash: Gash itself stays installed), and changes the login shell where needed.

## 7. Gash on WSL: Windows from the Linux terminal

Gash reads Windows and WSL from inside the distribution, and changes Windows only through a UAC prompt that you confirm. The `gash` commands work with every shell choice:

```bash
gash wsl doctor        # interop, Windows PATH, drives, networking, systemd: each failure with its remedy
gash wsl config        # the settings in force, from /etc/wsl.conf and your .wslconfig
gash wsl path 'C:\Users\me\Downloads'   # /mnt/c/Users/me/Downloads, and back with --windows
gash win doctor        # Windows: version, pending reboot, Defender, free disk space
gash win fix hosts-add 127.0.0.1 shop.test   # the Windows hosts file, through UAC
```

In Bash with Gash you also get short commands: `wex` opens Explorer in the current directory, `wtm` opens Task Manager, `wr` restarts WSL (it asks first), and `wslc` fixes Windows programs that time out on a WSL VM that has run for a long time. See [Windows and WSL](https://github.com/mauriziofonte/gash/blob/main/docs/windows/README.md) in the Gash documentation.

## 8. Create your SSH key

The installer does not create SSH keys: a key is personal and must have a passphrase. Create one **named** after its purpose and machine, protected by a strong passphrase:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519_work_laptop -C "you@work-laptop"
```

Type a passphrase when asked (a long sentence is easier to remember than a short random word). Share only the **public** key (`~/.ssh/id_ed25519_work_laptop.pub`), for example with your Git server. To use it for a host, add to `~/.ssh/config`:

```text
Host git.example.com
    IdentityFile ~/.ssh/id_ed25519_work_laptop
    IdentitiesOnly yes
```

To type the passphrase once per session, load the key into the agent: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_work_laptop`.

## 9. Desktop shortcuts

The automated installer creates two shortcuts. By hand: right-click the Desktop, `New` > `Shortcut`, and use:

* Terminal: `C:\Windows\System32\wsl.exe -d Debian --cd ~`
* Home folder: `\\wsl.localhost\Debian\home\USERNAME`

Replace `Debian` with `Ubuntu-24.04` or `Ubuntu-26.04` if that is your distribution, and `USERNAME` with your Linux username.

## 10. VS Code

1. Download VS Code from <https://code.visualstudio.com/> and install it on Windows
2. Install the **WSL** extension (`CTRL + SHIFT + x`, search "WSL")
3. In the Linux terminal, go to a project directory and run `code .`: VS Code installs its server in Linux and opens the folder

Install these extensions **while connected to WSL** (in a `code .` window), so that they run inside Linux:

1. **php cs fixer** by junstyle
2. **GitLens** by GitKraken
3. **PHP Intelephense** by Ben Mewburn
4. **Prettier - Code formatter** by Prettier
5. **PHP DocBlocker** by Neil Brayfield
6. **markdownlint** by David Anson
7. **Material Icon Theme** by Philipp Kief

Then `CTRL + SHIFT + p` > **Preferences: Open Remote Settings (JSON) (WSL: Debian)** and paste [vscode.json](/confs/vscode.json). It uses the php-cs-fixer that the extension ships, and the [Roboto Mono](https://fonts.google.com/specimen/Roboto+Mono) and [Source Code Pro](https://fonts.google.com/specimen/Source+Code+Pro) fonts: download them and install them on Windows.

## 11. Keeping the virtual disk small

With `sparseVhd=true` (section 2) and the TRIM timer enabled by the installer, space freed inside Linux goes back to Windows within a week. `sparseVhd` applies to new virtual disks only; to convert an existing distribution, from PowerShell:

```powershell
wsl --shutdown
wsl --manage Debian --set-sparse true
```

## 12. Keeping the stack up to date

| What | How |
|---|---|
| PHP, Apache, MariaDB, PostgreSQL, Redis | `sudo apt-get update && sudo apt-get upgrade`: they all come from apt repositories |
| A new release of this setup | Run the stack installer again (section 4): it adds what is new and leaves the rest as it is |
| Composer | `composer-self-update` in Bash with Gash, or `sudo composer self-update` and `sudo composer1 self-update` |
| Gash | `gash update` (back with `gash update --rollback`) |
| Node | `nvm install --lts --reinstall-packages-from=current` |
| WSL | `wsl --update` from PowerShell |

## 13. Troubleshooting

| Symptom | What to do |
|---|---|
| The installer says `Ports already in use by something outside this system` | Another distribution runs a stack on the same ports (they share one network): stop its services there, or stop it with `wsl --terminate <name>`, then run the installer again |
| The installer says `systemd is not running yet` | Run `wsl --terminate <distro>` from PowerShell, open the terminal again and run the installer again |
| The installer stopped half-way | Fix the cause it names and run it again. Logs: `~/.local/state/lamp-lapp-stack/` in Linux, `%LOCALAPPDATA%\WSL2Setup` in Windows |
| A site answers in Linux but not in the Windows browser | Windows does not know the name: `gash hte hosts windows`, then add the lines to the Windows hosts file (section 5). `gash hte doctor` checks it |
| Sites are down after `wsl --shutdown` | `gash hte doctor` names the cause; `gash hte service start` starts the stack |
| `code .`, `explorer.exe` and other Windows programs fail inside `tmux` or `screen` | `eval "$(gash wsl interop --export)"` points the shell at a live interop socket |
| Windows programs time out with `UtilAcceptVsock ... accept4 failed 110` | `wslc` in Bash with Gash, or `wsl --shutdown` from PowerShell |
| The virtual disk does not shrink | Check `sparseVhd=true` (section 2) and that `systemctl status fstrim.timer` shows it active |
| The disk is full (`No space left on device`) and you set a disk limit | Raise the limit with `wsl --manage <distro> --resize <size>GB` (section 2) |
| The Windows setup stops with `invalid options, nothing was changed` | The lines above it name each wrong option and the values it takes |
| Mirrored networking: a Linux server does not start because its port is in use | Windows already uses that port: stop the Windows program, or choose another port. Back to NAT: `networkingMode=nat` in `.wslconfig`, then `wsl --shutdown` |
| Mirrored networking: another computer cannot reach a Linux server | The Windows firewall blocks it: allow that port for inbound connections, or use NAT and serve from this PC only |

## 14. Uninstall

```powershell
wsl --unregister Debian
```

This deletes the distribution and **everything inside it** (home, databases). If you used the automated installer and it stopped half-way, also remove its state: `Remove-Item -Path "HKCU:\Software\WSL2Setup" -Force`.

## Disclaimer

By following this guide you take full responsibility for the changes made to your system. Neither the author nor the contributors are liable for any damage, including data loss. This setup is for **development machines**: do not use it on a production server.

## License

MIT License. See [LICENSE](/LICENSE).
