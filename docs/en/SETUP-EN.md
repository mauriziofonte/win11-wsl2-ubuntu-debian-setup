# Manual LAMP+LAPP Stack Setup on Windows 11 with WSL2, Debian 13 or Ubuntu 24.04/26.04, Native Services and VS Code

> Last updated at: _2026-10-28_. Targets: **Debian 13 (trixie)** (recommended), **Ubuntu 24.04 (noble)** and **Ubuntu 26.04 (resolute)**.
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
| Shell | Bash with Gash (default), or Zsh, or plain Bash | see [section 6](#6-your-shell-gash-or-an-alternative) |
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

## 2. Configure WSL on the Windows side (optional, recommended)

WSL reads its VM settings from `%UserProfile%\.wslconfig`. Without it, WSL may take up to half of your RAM and the virtual disk never shrinks. A sensible starting point for a 32 GB machine:

```ini
[wsl2]
# RAM given to the WSL VM: leave Windows at least a third of the total
memory=16GB
processors=8
swap=8GB
# Do not start the WSLg GUI stack if you do not use Linux GUI apps
guiApplications=false

[experimental]
# New virtual disks are sparse: space freed inside Linux goes back to Windows
sparseVhd=true
```

Run `wsl --shutdown` after editing it: the settings apply at the next WSL start. With Gash installed, `gash wsl config` shows every setting in force and where it comes from (section 7).

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

Options go after `bash -s --`, for example `... | bash -s -- --yes --php "8.4 8.3 7.4" --shell zsh`:

| Option | Effect |
|---|---|
| `-y`, `--yes` | Never prompt, take the defaults |
| `--php "X.Y ..."` | PHP versions to install (default: all, 5.6 to 8.5) |
| `--pg N` | PostgreSQL major version (default: 18) |
| `--shell gash\|zsh\|bash` | Your interactive shell: Bash with Gash (default), Zsh with Oh My Zsh, or the distribution's Bash unchanged (see [section 6](#6-your-shell-gash-or-an-alternative)) |
| `--no-gash` | Do not install Gash (and so no `gash hte`); implies `--shell bash` |
| `--no-hte` | Install Gash but do not set up `gash hte` |
| `--hte-ports standard\|high` | Ports for local sites: 80/443 (default) or high ports (8080/8443) |
| `--no-node` | Do not install nvm and Node |
| `--wsl`, `--no-wsl` | Force or skip the WSL tuning (default: detected) |
| `--tmp-size SIZE` | Size cap of `/tmp` on WSL, e.g. `6G` or `25%` (default: `25%`) |

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

With `--shell gash` (the default), interactive Bash shells load Gash, which also defines `php85` ... `php56`, `composer85` ... `composer56`, `1composer72` ... `1composer56` and `composer-self-update`. With `--shell zsh` or `--shell bash`, Gash leaves your shell alone and only the `gash` command is installed (in `~/.local/bin`), so `gash hte` works the same.

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
| Zsh with Oh My Zsh | `--shell zsh` | Zsh as your login shell, the plugins and themes of [Oh My Zsh](https://ohmyz.sh/), nvm and the `gash` command in `~/.zshrc` | No Gash functions and aliases: use `php8.4` and `gash run --runtime php:8.4 -- composer install` instead of `php84` and `composer84` |
| Plain Bash | `--shell bash` | The distribution's Bash as it is, with the `gash` command in `~/.local/bin` | The same as for Zsh |
| No Gash at all | `--no-gash` | No `gash` command | No `gash hte`: serve your sites with the system Apache (enabled by its package) and edit its virtual hosts yourself |

Other shells and prompts work on top of any choice: install [fish](https://fishshell.com/) with `sudo apt-get install -y fish`, or the [Starship](https://starship.rs/) prompt with its installer. Starship replaces the prompt, so pair it with `--shell zsh` or `--shell bash` rather than with Gash's own prompt.

`--shell` only adds: running the installer again with another `--shell` sets the new shell up and keeps the old one. `chsh -s /bin/bash` (or `/usr/bin/zsh`) changes your login shell back at any time.

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

With `sparseVhd=true` (section 2) and the TRIM timer enabled by the installer, space freed inside Linux goes back to Windows within a week. To convert an existing distribution, from PowerShell:

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

## 14. Uninstall

```powershell
wsl --unregister Debian
```

This deletes the distribution and **everything inside it** (home, databases). If you used the automated installer and it stopped half-way, also remove its state: `Remove-Item -Path "HKCU:\Software\WSL2Setup" -Force`.

## Disclaimer

By following this guide you take full responsibility for the changes made to your system. Neither the author nor the contributors are liable for any damage, including data loss. This setup is for **development machines**: do not use it on a production server.

## License

MIT License. See [LICENSE](/LICENSE).
