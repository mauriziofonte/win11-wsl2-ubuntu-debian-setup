# What CI verifies

The guide makes claims: which versions you get, what each installer changes, which commands work. The [CI workflow](/.github/workflows/ci.yml) checks them on real systems at every push and pull request, and every Monday against the current state of the package repositories (so that a package removed upstream shows up as a red build, not as a broken install for the next reader).

## Jobs

| Job | Runs on | What it does |
|---|---|---|
| Lint | Ubuntu | ShellCheck on every shell script; the documents against the installers and Gash ([check-docs.py](check-docs.py)) |
| PowerShell | Windows | PSScriptAnalyzer on both PowerShell scripts, a parse in Windows PowerShell 5.1 and PowerShell 7, and `win11.ps1 -DryRun -Unattended` for each distribution |
| WSL2 | Windows | [wsl/run.ps1](wsl/run.ps1): the Windows setup end to end, on a real WSL2, for Debian 13, Ubuntu 24.04 and Ubuntu 26.04 |
| Plain machine | Ubuntu + Docker | [container/run.sh](container/run.sh): the stack installer in a container with systemd, with other options, and the manual steps of the guide |

## The WSL2 job

On a Windows runner, for each distribution:

1. `wsl --install -d <distro> --no-launch`, then a user with passwordless `sudo`. This stands in for the user name and password that you choose when the distribution starts for the first time: everything after it is what you run.
2. `install/win11.ps1 -Unattended` in Windows PowerShell 5.1, with this repository's copy of the stack installer. It installs the whole stack and restarts the distribution.
3. The two Desktop shortcuts exist, and Windows opens the home folder they point to.
4. [verify-stack.sh](verify-stack.sh) checks the result (the list below), and runs the guide's "Your first local site" commands exactly as written.
5. The lines of `gash hte hosts windows` go in the Windows hosts file, and `curl.exe` on Windows opens `https://shop.test/`: WSL's localhost forwarding and the hosts lines work together.
6. `wsl --terminate`, then the checks again: services, the local site, `/tmp` on tmpfs and the hosts names come back at boot.
7. `win11.ps1` again: it reports the distribution as already installed, and the stack installer changes nothing.

## The plain-machine job

[container/run.sh](container/run.sh) starts a container of the distribution with systemd as PID 1 and a user `dev`, then:

1. holds port 3306 from a process in another PID namespace on the same network (what another WSL distribution looks like) and checks that the installer stops with status 1 and names the port;
2. runs the installer as the guide says (`... | bash -s -- OPTIONS`) and checks the result with `verify-stack.sh`;
3. runs it again and checks that it changes nothing;
4. restarts the container and checks again.

| Distribution | Options | Covers |
|---|---|---|
| Debian 13 | `--php 8.3 --no-gash --no-node` | A subset of PHP, no Gash: the system Apache keeps serving |
| Ubuntu 24.04 | `--php "8.4 5.6" --shell bash --no-node` | The oldest and a recent PHP, Composer 1, Gash as a command only, the mariadb.org repository |
| Ubuntu 26.04 | `--php "8.4 7.4" --shell zsh --hte-ports high --wsl --tmp-size 2G` | Zsh with Oh My Zsh, high ports, the WSL tuning forced on a non-WSL system |

The manual steps run too: on Ubuntu 24.04, the blocks of sections 4.2 and 4.3 of the guide run as written, one after the other, and the result is checked.

## What verify-stack.sh checks

Each line of its output names the section of the guide it backs. In short:

| Area | Facts |
|---|---|
| System | Debian 13, Ubuntu 24.04 or Ubuntu 26.04; systemd is PID 1 |
| WSL tuning (4.1) | `/etc/wsl.conf` keys; `/tmp` on tmpfs with the size cap (after a restart); `fstrim.timer` enabled and active despite the virtualization condition; `getty@tty1` masked |
| PHP (4.3) | Each version runs, has every extension of the list (OPcache built into 8.5) and its FPM; the newest is the default `php` |
| Apache | 2.4; with `gash hte` the system Apache and the system PHP-FPM services are stopped and disabled; without it, the system Apache runs |
| MariaDB (4.4) | 11.8; `sudo mariadb` as root; `utf8mb4`, `utf8mb4_unicode_ci`, 1 GB buffer pool, no binary log, `NO_ENGINE_SUBSTITUTION`; user `default` with the password of `~/.mysql-pass` (mode 600), all privileges; no anonymous users, no `test` database; loopback only |
| PostgreSQL (4.5) | 18, one cluster on 5432; your role is a superuser with its own database (peer); `default` logs in with `~/.pgsql-pass` and owns `defaultdb`; loopback only |
| Redis | Answers; loopback only |
| Composer (4.6) | `composer` is 2.x, `composer1` is 1.x |
| Your shell (4.7, 6) | Gash: `~/.bashrc` loads it, interactive Bash has its functions and the `phpXY`, `composerXY`, `1composerXY` aliases. Zsh: login shell, Oh My Zsh, `gash` found. Bash: `gash` linked in `~/.local/bin` |
| `gash hte` (4.7, 5) | Linger and the `gash-hte.service` user unit; the port setting; the guide's first site answers with PHP 8.4 over HTTP/2, its name is in `/etc/hosts`, its certificate is ECDSA and valid 10 years; Apache runs as your user and no PHP-FPM master as root; `site modify --php 7.4` switches the version; `gash hte doctor` passes |
| Gash on WSL (5, 7) | `gash hte hosts windows`, `gash wsl info`, `gash win info` (Windows read through interop), `gash win fix hosts-add --dry-run` |
| Node (4.8) | nvm 0.40.8, and the current Node is the LTS |

## Running them yourself

```bash
python3 tests/check-docs.py                          # needs only Python 3
GASH_REPO=../gash python3 tests/check-docs.py        # with a checkout of Gash next to this one
tests/container/run.sh mirror.gcr.io/library/debian:13 minimal   # needs Docker; takes minutes
```

`tests/wsl/run.ps1` installs a distribution, edits the Windows hosts file and creates Desktop shortcuts: run it only on a disposable Windows machine.
