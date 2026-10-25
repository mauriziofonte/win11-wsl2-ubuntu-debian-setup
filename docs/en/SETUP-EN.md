# Manual LAMP+LAPP Stack Setup on Windows 11 with WSL2, Debian 13 or Ubuntu 24.04/26.04, Native Services and VS Code

> Last updated at: _2026-10-25_. Targets: **Debian 13 (trixie)** (recommended), **Ubuntu 24.04 (noble)** and **Ubuntu 26.04 (resolute)**.

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
| MariaDB | 11.8 LTS (EOL 2030-02-13) | Debian 13 and Ubuntu 26.04 themselves; [mariadb.org](https://mariadb.org/download/) on Ubuntu 24.04 (which ships 10.11) |
| PostgreSQL | 18 | [pgdg](https://wiki.postgresql.org/wiki/Apt) |
| Redis | distribution | distribution |
| Composer | 2 and 1 | [getcomposer.org](https://getcomposer.org/download/), checksum verified |
| Local sites | `gash hte` | [Gash](https://github.com/mauriziofonte/gash) |
| Node | LTS via nvm | [nvm](https://github.com/nvm-sh/nvm) |

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

Run `wsl --shutdown` after editing it: the settings apply at the next WSL start.

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

Options go after `bash -s --`, for example `... | bash -s -- --yes --php "8.4 8.3 7.4"`:

| Option | Effect |
|---|---|
| `-y`, `--yes` | Never prompt, take the defaults |
| `--php "X.Y ..."` | PHP versions to install (default: all, 5.6 to 8.5) |
| `--pg N` | PostgreSQL major version (default: 18) |
| `--no-gash` | Do not install Gash (and so no `gash hte`) |
| `--no-hte` | Install Gash but do not set up `gash hte` |
| `--hte-ports standard\|high` | Ports for local sites: 80/443 (default) or high ports |
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

```bash
sudo apt-get install -y ca-certificates curl lsb-release postgresql-common
curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
sudo dpkg -i /tmp/debsuryorg-archive-keyring.deb
echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
sudo apt-get update
```

Ubuntu 24.04 ships MariaDB 10.11, so it also needs the mariadb.org repository:

```bash
curl -fsSL https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version=mariadb-11.8 --skip-maxscale --skip-tools
sudo apt-get update
```

The `ppa:ondrej/php` used by the previous versions of this guide is being merged into packages.sury.org, and Ubuntu 26.04 is served only there. If your Ubuntu already uses the PPA, the installer keeps it and does not add sury, so the same packages never come from two sources.

### 4.3 Packages

For every PHP version `X.Y` the installer adds `phpX.Y-` + `cli fpm bcmath bz2 curl gd gmp igbinary imagick imap intl mbstring mcrypt memcached msgpack mysql opcache pgsql readline redis soap sqlite3 xml xsl zip` (PHP 8.5 has opcache built in), then:

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

`default` is a reserved word in SQL: always quote it (`"default"`) in your own statements.

### 4.6 Composer

`composer` (2.x) and `composer1` (1.x, for legacy projects) are downloaded to `/usr/local/bin` and checked against the published SHA-256. Composer 1 does not support recent PHP versions (with PHP 8.4+ it prints deprecation notices): run it with an old PHP, e.g. `1composer72`, the Gash alias for `php7.2 /usr/local/bin/composer1`.

### 4.7 Gash and `gash hte`

[Gash](https://github.com/mauriziofonte/gash) is a Bash environment with a prompt, helpers and the `gash hte` local-sites manager. The installer runs the Gash installer, then:

```bash
gash hte install --yes --ports standard
```

This uses `sudo` once to install a small helper for `/etc/hosts`, allow your user to bind ports 80 and 443 (`net.ipv4.ip_unprivileged_port_start = 80`), stop and disable the system Apache, and enable a systemd **user** unit (`gash-hte.service`) that starts the stack at boot. Since `gash hte` runs its own PHP-FPM masters, the installer then disables the system `phpX.Y-fpm` services: they would only use memory (about 70 MB per version).

In interactive shells Gash also defines `php85` ... `php56`, `composer85` ... `composer56`, `1composer72` ... `1composer56` and `composer-self-update`.

### 4.8 nvm and Node

nvm is installed from its official script, then `nvm install --lts`.

## 5. Your first local site

```bash
mkdir -p ~/sites/shop/public && echo '<?php phpinfo();' > ~/sites/shop/public/index.php
cd ~/sites/shop
gash hte site create --domain shop.test --docroot public --php 8.4
curl -k https://shop.test/ | head
```

Inside Linux, `gash hte` keeps the names in `/etc/hosts`. Windows has its own hosts file: `gash hte hosts windows` prints the lines to add to `C:\Windows\System32\drivers\etc\hosts` (edit it as Administrator). Then open `https://shop.test/` in your Windows browser.

Useful commands: `gash hte site list`, `gash hte site modify --domain shop.test --php 7.4`, `gash hte site remove --domain shop.test --yes`, `gash hte doctor`. See the [gash hte guide](https://github.com/mauriziofonte/gash/blob/main/docs/hte.md).

## 6. Create your SSH key

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

## 7. Desktop shortcuts

The automated installer creates two shortcuts. By hand: right-click the Desktop, `New` > `Shortcut`, and use:

* Terminal: `C:\Windows\System32\wsl.exe -d Debian --cd ~`
* Home folder: `\\wsl.localhost\Debian\home\USERNAME`

Replace `Debian` with `Ubuntu-24.04` or `Ubuntu-26.04` if that is your distribution, and `USERNAME` with your Linux username.

## 8. VS Code

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

Then `CTRL + SHIFT + p` > **Preferences: Open Remote Settings (JSON) (WSL: Debian)** and paste [vscode.json](/confs/vscode.json), replacing `##LINUX_USERNAME##` with your Linux username. It uses the [Roboto](https://fonts.google.com/specimen/Roboto) and [Source Code Pro](https://fonts.google.com/specimen/Source+Code+Pro) fonts: download them and install them on Windows.

## 9. Keeping the virtual disk small

With `sparseVhd=true` (section 2) and the TRIM timer enabled by the installer, space freed inside Linux goes back to Windows within a week. To convert an existing distribution, from PowerShell:

```powershell
wsl --shutdown
wsl --manage Debian --set-sparse true
```

## 10. Uninstall

```powershell
wsl --unregister Debian
```

This deletes the distribution and **everything inside it** (home, databases). If you used the automated installer and it stopped half-way, also remove its state: `Remove-Item -Path "HKCU:\Software\WSL2Setup" -Force`.

## Disclaimer

By following this guide you take full responsibility for the changes made to your system. Neither the author nor the contributors are liable for any damage, including data loss. This setup is for **development machines**: do not use it on a production server.

## License

MIT License. See [LICENSE](/LICENSE).
