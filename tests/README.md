# What CI verifies

The guide makes claims: which versions you get, what each installer changes, which commands work. The [CI workflow](/.github/workflows/ci.yml) checks them on real systems at every push and pull request, and every Monday against the current state of the package repositories (so that a package removed upstream shows up as a red build, not as a broken install for the next reader).

## Jobs

| Job | Runs on | What it does |
|---|---|---|
| Lint | Ubuntu | ShellCheck on every shell script; the documents against the installers and Gash ([check-docs.py](check-docs.py)) |
| PowerShell | Windows | PSScriptAnalyzer and a parse in Windows PowerShell 5.1 of every PowerShell script; [powershell/unit.ps1](powershell/unit.ps1) and [powershell/dry-run.ps1](powershell/dry-run.ps1) (below) |
| WSL2 | Windows | [wsl/run.ps1](wsl/run.ps1): the Windows setup end to end, on a real WSL2, for Debian 13, Ubuntu 24.04 and Ubuntu 26.04, each with other options |
| Plain machine | Ubuntu + Docker | [container/run.sh](container/run.sh): the stack installer in a container with systemd, with other options, and the manual steps of the guide |

## The PowerShell job

* [powershell/unit.ps1](powershell/unit.ps1), in Windows PowerShell 5.1 and in PowerShell 7, loads the WSL settings functions of `win11.ps1` on their own (without running the setup) and checks: the three profiles against the tables of section 2 of both guides; the `.wslconfig` example of both guides against what the setup writes; the swap and the disk limit it proposes; that merging into an existing `.wslconfig` keeps your comments, keys and sections, changes a key in place, and changes nothing the second time.
* [powershell/dry-run.ps1](powershell/dry-run.ps1) runs `win11.ps1 -DryRun -Unattended`, each time with a `%UserProfile%` of its own: every step for each distribution, with a new `.wslconfig` (Balanced, NAT, no WSLg, the base settings); every option at once; an existing `.wslconfig` kept as it is without options, changed only where options say so, untouched when it already matches; and each invalid option (and several at once) refused with status 1, the problem named, before step 2 and with `.wslconfig` unchanged.

## The WSL2 job

On a Windows runner, for each distribution:

1. `wsl --help` lists `--vhd-size` and `--resize`, which the disk limit uses. `wsl --install -d <distro> --no-launch`, then a user with passwordless `sudo`. This stands in for the user name and password that you choose when the distribution starts for the first time: everything after it is what you run.
2. `install/win11.ps1 -Unattended` in Windows PowerShell 5.1, with this repository's copy of the stack installer and the options of the leg (below). It writes `.wslconfig`, installs the whole stack and restarts the distribution. Then `.wslconfig` must hold exactly the settings of the options and the profile, the profile computed from the runner's RAM and processors; with a `.wslconfig` of your own, your lines stay and a backup copy holds the file as it was.
3. The two Desktop shortcuts exist, and Windows opens the home folder they point to.
4. [verify-stack.sh](verify-stack.sh) checks the result (the list below), and runs the guide's "Your first local site" commands exactly as written. Inside the virtual machine: the RAM, the processors, the swap, the network mode (`wslinfo --networking-mode`) are those of `.wslconfig`, and the root file system fits the disk limit (at most its size, at least 90% of it).
5. The lines of `gash hte hosts windows` go in the Windows hosts file, and `curl.exe` on Windows opens `https://shop.test/`: WSL's localhost forwarding (or mirrored networking) and the hosts lines work together.
6. `wsl --terminate`, then the checks again: services, the local site, `/tmp` on tmpfs and the hosts names come back at boot, and `gash hte hosts windows` has nothing left to add.
7. `win11.ps1` again: it reports the distribution as already installed, `.wslconfig` stays as it is, and the stack installer changes nothing.

| Distribution | Options | Covers |
|---|---|---|
| Debian 13 | none | The defaults: Bash with Gash, the Balanced profile, NAT, no WSLg, no disk limit, `initTimeout` 30000 |
| Ubuntu 24.04 | `-PresetWslConfig -VmProfile Light -VhdSizeGB 20 -WslInitTimeout 45000 -Shell fish` | A `.wslconfig` of your own (unattended: only the profile and the disk limit change in it), a disk limit on a distribution that exists already (`wsl --manage --resize`), Fish |
| Ubuntu 26.04 | `-VmProfile Performance -WslNetworking mirrored -WslAppendWindowsPath false -Shell bash-plus` | Mirrored networking (Windows still opens the site); where it leaves Linux without DNS, the fallback to NAT instead, with a warning on the run, no Windows folders on the Linux `PATH` (and `gash win` still works), Bash with fzf, zoxide and starship |

## The plain-machine job

[container/run.sh](container/run.sh) starts a container of the distribution with systemd as PID 1 and a user `dev`, then:

1. holds port 3306 from a process in another PID namespace on the same network (what another WSL distribution looks like) and checks that the installer stops with status 1 and names the port;
2. runs the installer as the guide says (`... | bash -s -- OPTIONS`) and checks the result with `verify-stack.sh`;
3. runs it again and checks that it changes nothing;
4. restarts the container and checks again.

| Distribution | Options | Covers |
|---|---|---|
| Debian 13 | `--php 8.3 --no-gash --no-node` | A subset of PHP, no Gash: the system Apache keeps serving |
| Ubuntu 24.04 | `--php "8.4 5.6" --shell bash-plus --no-node` | The oldest and a recent PHP, Composer 1, Gash as a command only, the mariadb.org repository; Bash with fzf (0.44, its key bindings from `/usr/share/doc`), zoxide, and starship from its release (Ubuntu 24.04 does not package it) |
| Ubuntu 26.04 | `--php "8.4 7.4" --shell zsh --hte-ports high --wsl --tmp-size 2G --wsl-init-timeout 45000` | The minimal Zsh, high ports, the WSL tuning forced on a non-WSL system, with its options |
| Debian 13 | `--php 8.4 --shell fish` | Fish: the hand-over from an interactive Bash, fzf, zoxide, starship, the `gash` command, Node through the `nvm` of fish |

The manual steps run too: on Ubuntu 24.04, the blocks of sections 4.2 and 4.3 of the guide run as written, one after the other, and the result is checked.

## What verify-stack.sh checks

Each line of its output names the section of the guide it backs. In short:

| Area | Facts |
|---|---|
| System | Debian 13, Ubuntu 24.04 or Ubuntu 26.04; systemd is PID 1 |
| WSL tuning (4.1) | `/etc/wsl.conf` keys (`initTimeout` and `appendWindowsPath` included, and the Windows folders on `PATH` or not); `/tmp` on tmpfs with the size cap (after a restart); `fstrim.timer` enabled and active despite the virtualization condition; `getty@tty1` masked |
| PHP (4.3) | Each version runs, has every extension of the list (OPcache built into 8.5) and its FPM; the newest is the default `php` |
| Apache | 2.4; with `gash hte` the system Apache and the system PHP-FPM services are stopped and disabled; without it, the system Apache runs |
| MariaDB (4.4) | 11.8; `sudo mariadb` as root; `utf8mb4`, `utf8mb4_unicode_ci`, 1 GB buffer pool, no binary log, `NO_ENGINE_SUBSTITUTION`; user `default` with the password of `~/.mysql-pass` (mode 600), all privileges; no anonymous users, no `test` database; loopback only |
| PostgreSQL (4.5) | 18, one cluster on 5432; your role is a superuser with its own database (peer); `default` logs in with `~/.pgsql-pass` and owns `defaultdb`; loopback only |
| Redis | Answers; loopback only |
| Composer (4.6) | `composer` is 2.x, `composer1` is 1.x |
| The WSL virtual machine (2) | RAM, processors, swap and network mode match `.wslconfig`; the root file system fits the disk limit (on WSL, when the test passes the values) |
| Gash and your shell (4.7, 6) | Gash: `~/.bashrc` loads it, interactive Bash has its functions and the `phpXY`, `composerXY`, `1composerXY` aliases; with another shell, `gash` is linked in `~/.local/bin` and `~/.bashrc` does not load Gash. bash-plus: `~/.inputrc`, fzf key bindings, zoxide, the starship prompt, the history size. Zsh: login shell, no Oh My Zsh, autosuggestions, syntax highlighting, fzf, zoxide, starship, `gash` and `node` found. Fish: Bash stays the login shell and hands over to fish only when interactive, fzf, zoxide, starship, `gash` found, `node` is the LTS of nvm. Gash and plain Bash: the login shell is Bash |
| `gash hte` (4.7, 5) | Linger and the `gash-hte.service` user unit; the port setting; the guide's first site answers with PHP 8.4 over HTTP/2, its name is in `/etc/hosts`, its certificate is ECDSA and valid 10 years; Apache runs as your user and no PHP-FPM master as root; `site modify --php 7.4` switches the version; `gash hte doctor` passes |
| Gash on WSL (5, 7) | `gash hte hosts windows`, `gash wsl info`, `gash win info` (Windows read through interop), `gash win fix hosts-add --dry-run` |
| Node (4.8) | nvm 0.40.8, and the current Node is the LTS |

## Running them yourself

```bash
python3 tests/check-docs.py                          # needs only Python 3
pwsh tests/powershell/unit.ps1                       # needs PowerShell; dry-run.ps1 needs Windows
GASH_REPO=../gash python3 tests/check-docs.py        # with a checkout of Gash next to this one
tests/container/run.sh mirror.gcr.io/library/debian:13 minimal   # needs Docker; takes minutes
```

`tests/wsl/run.ps1` installs a distribution, edits the Windows hosts file and creates Desktop shortcuts: run it only on a disposable Windows machine.
