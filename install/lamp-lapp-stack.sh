#!/usr/bin/env bash

# LAMP+LAPP development stack installer for Debian 13 (trixie), Ubuntu 24.04 (noble) and
# Ubuntu 26.04 (resolute), on WSL2 or on a plain machine.
#
# Installs: PHP 5.6-8.5 (CLI + FPM, packages.sury.org), Apache 2.4, MariaDB 11.8 LTS,
# PostgreSQL 18 (pgdg), Redis, Composer 2 + 1, Gash (+ `gash hte` for local sites), nvm + Node LTS,
# and the interactive shell you choose: Bash with Gash (default), Bash with fzf/zoxide/starship,
# a minimal Zsh, Fish, or the plain Bash.
# On WSL it also applies the WSL base tuning: systemd, /etc/wsl.conf, /tmp on tmpfs, TRIM, no tty getty.
#
# The script converges: every step checks the current state and changes only what differs,
# so running it again is safe and is the way to resume after a failure.
#
# Author: Maurizio Fonte (https://www.mauriziofonte.it)
# Version: 2.1.0
# Release Date: 2023-09-04
# Last Update: 2026-10-29
# License: MIT License
#
# Report issues: https://github.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup/issues

{ # this ensures the entire script is downloaded #

    set -Eeuo pipefail

    LLS_VERSION="2.1.0"
    LLS_PHP_ALL="5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3 8.4 8.5"
    LLS_PHP_MODS="cli fpm bcmath bz2 curl gd gmp igbinary imagick imap intl mbstring mcrypt memcached msgpack mysql opcache pgsql readline redis soap sqlite3 xml xsl zip"
    LLS_MARIADB_SERIES="11.8"
    LLS_NVM_VERSION="v0.40.8"
    LLS_GASH_INSTALLER="https://raw.githubusercontent.com/mauriziofonte/gash/main/install.sh"
    # starship for the distributions that do not package it (Ubuntu 24.04): a pinned release, checked by SHA-256.
    LLS_STARSHIP_VERSION="1.27.0"
    LLS_STARSHIP_SHA256_X86_64="10c8eb4cb3b761d9bf59ea828444c2dab36c900b7d69a69e08814b286969df89"
    LLS_STARSHIP_SHA256_AARCH64="341f5cbf24699fa0b27ec88965ad25f862ea09e15d35a543fd6ffdff1d2aa00d"
    LLS_WSL_INIT_TIMEOUT="30000"
    LLS_MANAGED="# Managed by lamp-lapp-stack.sh: re-running the installer rewrites this file."

    # Options (see lls_usage)
    OPT_YES=0
    OPT_PHP="$LLS_PHP_ALL"
    OPT_PG="18"
    OPT_GASH=1
    OPT_HTE=1
    OPT_NODE=1
    OPT_WSL=auto
    OPT_TMP_SIZE="25%"
    OPT_HTE_PORTS="standard"
    OPT_SHELL=""
    OPT_WSL_INIT_TIMEOUT=""
    OPT_WSL_APPEND_PATH=""

    lls_echo() {
        local color="\e[1;97m"
        case "${1-}" in
            info) color="\e[1;92m"; shift ;;
            step) color="\e[1;94m"; shift ;;
            log) color="\e[36m"; shift ;;
            warning) color="\e[33m"; shift ;;
            error) color="\e[31m"; shift ;;
        esac
        printf "${color}%s\e[0m\n" "$*"
    }

    lls_usage() {
        cat <<EOF
lamp-lapp-stack.sh $LLS_VERSION - LAMP+LAPP stack for Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 (WSL2 or plain)

Usage: lamp-lapp-stack.sh [options]
       curl -fsSL https://wsl.mauriziofonte.it/lamp | bash -s -- [options]

  -y, --yes            never prompt, take the defaults (needed without a terminal)
  --php "X.Y ..."      PHP versions to install (default: "$LLS_PHP_ALL")
  --pg N               PostgreSQL major from pgdg (default: $OPT_PG)
  --shell S            interactive shell (asked when not given, on a terminal without --yes):
                         gash       Bash with Gash (the default)
                         bash-plus  Bash with fzf, zoxide and the starship prompt
                         zsh        Zsh with autosuggestions and syntax highlighting (no Oh My Zsh)
                         fish       Fish for the terminal; Bash stays the login shell and runs the scripts
                         bash       the distribution's Bash, unchanged
                       with every shell but gash, the gash command is still installed, for gash hte
  --no-gash            do not install Gash (implies --no-hte and --shell bash)
  --no-hte             install Gash but do not run "gash hte install"
  --hte-ports P        ports for gash hte: standard (80/443) or high (default: standard)
  --no-node            do not install nvm and Node LTS
  --wsl | --no-wsl     force or skip the WSL base tuning (default: detected)
  --tmp-size SIZE      /tmp tmpfs cap on WSL, a size or a % of RAM (default: $OPT_TMP_SIZE)
  --wsl-init-timeout MS
                       /etc/wsl.conf [boot] initTimeout, the milliseconds WSL waits for systemd
                       (1000-600000; default: $LLS_WSL_INIT_TIMEOUT, an existing value is kept)
  --wsl-append-windows-path true|false
                       /etc/wsl.conf [interop] appendWindowsPath (default: left as it is)
  -h, --help           this help

Run it as your normal user (it uses sudo). Running it again is safe.
EOF
    }

    lls_parse_args() {
        while [ $# -gt 0 ]; do
            case "$1" in
                -y | --yes) OPT_YES=1 ;;
                --php) OPT_PHP="${2-}"; shift ;;
                --pg) OPT_PG="${2-}"; shift ;;
                --no-gash) OPT_GASH=0; OPT_HTE=0 ;;
                --no-hte) OPT_HTE=0 ;;
                --no-node) OPT_NODE=0 ;;
                --wsl) OPT_WSL=1 ;;
                --no-wsl) OPT_WSL=0 ;;
                --tmp-size) OPT_TMP_SIZE="${2-}"; shift ;;
                --hte-ports) OPT_HTE_PORTS="${2-}"; shift ;;
                --shell) OPT_SHELL="${2-}"; shift ;;
                --wsl-init-timeout) OPT_WSL_INIT_TIMEOUT="${2-}"; shift ;;
                --wsl-append-windows-path) OPT_WSL_APPEND_PATH="${2-}"; shift ;;
                -h | --help) lls_usage; exit 0 ;;
                *) lls_echo error "Unknown option: $1"; lls_usage; exit 1 ;;
            esac
            shift
        done

        local v
        for v in $OPT_PHP; do
            case " $LLS_PHP_ALL " in
                *" $v "*) ;;
                *) lls_echo error "Unsupported PHP version: $v (supported: $LLS_PHP_ALL)"; exit 1 ;;
            esac
        done
        [ -n "$OPT_PHP" ] || { lls_echo error "--php needs at least one version"; exit 1; }
        [[ "$OPT_PG" =~ ^[0-9]+$ ]] || { lls_echo error "--pg needs a major version number"; exit 1; }
        [[ "$OPT_TMP_SIZE" =~ ^[0-9]+[KMG%]?$ ]] || { lls_echo error "--tmp-size: use e.g. 6G or 25%"; exit 1; }
        [[ "$OPT_HTE_PORTS" =~ ^(standard|high)$ ]] || { lls_echo error "--hte-ports: standard or high"; exit 1; }
        if [ -n "$OPT_WSL_INIT_TIMEOUT" ]; then
            [[ "$OPT_WSL_INIT_TIMEOUT" =~ ^[0-9]+$ ]] && [ "$OPT_WSL_INIT_TIMEOUT" -ge 1000 ] && [ "$OPT_WSL_INIT_TIMEOUT" -le 600000 ] ||
                { lls_echo error "--wsl-init-timeout: milliseconds, from 1000 to 600000"; exit 1; }
        fi
        [[ "$OPT_WSL_APPEND_PATH" =~ ^(|true|false)$ ]] || { lls_echo error "--wsl-append-windows-path: true or false"; exit 1; }
        if [ "$OPT_WSL" = 0 ] && [ -n "$OPT_WSL_INIT_TIMEOUT$OPT_WSL_APPEND_PATH" ]; then
            lls_echo error "--wsl-init-timeout and --wsl-append-windows-path set /etc/wsl.conf: they exclude --no-wsl"
            exit 1
        fi
        if [ -n "$OPT_SHELL" ]; then
            [[ "$OPT_SHELL" =~ ^(gash|bash-plus|zsh|fish|bash)$ ]] || { lls_echo error "--shell: gash, bash-plus, zsh, fish or bash"; exit 1; }
            if [ "$OPT_SHELL" = gash ] && [ "$OPT_GASH" -eq 0 ]; then
                lls_echo error "--shell gash and --no-gash exclude each other"
                exit 1
            fi
        fi
    }

    # The shell, when no --shell was given: asked on a terminal, else Bash with Gash (plain Bash with --no-gash).
    lls_choose_shell() {
        [ -z "$OPT_SHELL" ] || return 0
        local default=gash reply
        [ "$OPT_GASH" -eq 1 ] || default=bash
        if [ "$OPT_YES" -eq 1 ] || ! { : </dev/tty; } 2>/dev/null; then
            OPT_SHELL="$default"
            return 0
        fi
        echo "Interactive shell:"
        [ "$OPT_GASH" -eq 1 ] && echo "  1) gash       Bash with Gash (recommended)"
        echo "  2) bash-plus  Bash with fzf, zoxide and the starship prompt"
        echo "  3) zsh        Zsh with autosuggestions and syntax highlighting"
        echo "  4) fish       Fish for the terminal, Bash for the scripts"
        echo "  5) bash       the distribution's Bash, unchanged"
        read -r -p "Your choice [Enter = $default] " reply </dev/tty || reply=""
        case "$reply" in
            1) OPT_SHELL=gash ;;
            2) OPT_SHELL=bash-plus ;;
            3) OPT_SHELL=zsh ;;
            4) OPT_SHELL=fish ;;
            5) OPT_SHELL=bash ;;
            *) OPT_SHELL="$default" ;;
        esac
        if [ "$OPT_SHELL" = gash ] && [ "$OPT_GASH" -eq 0 ]; then
            OPT_SHELL=bash
        fi
    }

    # Yes/no question; the default wins with --yes or without a terminal.
    lls_ask() {
        local question="$1" default="$2" reply
        if [ "$OPT_YES" -eq 1 ] || ! { : </dev/tty; } 2>/dev/null; then
            [ "$default" = "y" ]
            return
        fi
        read -r -p "$question [$([ "$default" = "y" ] && echo Y/n || echo y/N)] " reply </dev/tty || reply=""
        reply="${reply:-$default}"
        [[ "$reply" =~ ^[Yy]$ ]]
    }

    lls_apt() {
        sudo env DEBIAN_FRONTEND=noninteractive apt-get -y -q \
            -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
    }

    # Writes stdin to a root-owned file only when the content differs.
    # Returns 0 when the file changed, 1 when it was already up to date.
    lls_put_file() {
        local dst="$1" mode="${2:-0644}" tmp
        tmp="$(mktemp)"
        cat >"$tmp"
        if sudo cmp -s "$tmp" "$dst" 2>/dev/null; then
            rm -f "$tmp"
            return 1
        fi
        sudo install -D -m "$mode" "$tmp" "$dst"
        rm -f "$tmp"
        lls_echo log "  wrote $dst"
        return 0
    }

    # Sets key=value inside [section] of an INI file, keeping every other line.
    # Returns 0 when the file changed.
    lls_ini_set() {
        local file="$1" section="$2" key="$3" value="$4"
        sudo touch "$file"
        sudo awk -v sec="$section" -v key="$key" -v val="$value" '
            function flush() { if (insec && !done) { print key "=" val; done = 1 } }
            /^[[:space:]]*\[/ {
                flush()
                insec = ($0 ~ "^[[:space:]]*\\[" sec "\\][[:space:]]*$")
                print; next
            }
            insec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { if (!done) { print key "=" val; done = 1 } next }
            { print }
            END { flush(); if (!done) { print ""; print "[" sec "]"; print key "=" val } }
        ' "$file" | lls_put_file "$file" 0644
    }

    # Prints the value of key inside [section] of an INI file (nothing when it is not set).
    lls_ini_get() {
        local file="$1" section="$2" key="$3"
        [ -r "$file" ] || return 0
        awk -v sec="$section" -v key="$key" '
            /^[[:space:]]*\[/ { insec = ($0 ~ "^[[:space:]]*\\[" sec "\\][[:space:]]*$"); next }
            insec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }
        ' "$file"
    }

    lls_on_error() {
        lls_echo error "FAILED at line $1 (exit $2). Fix the cause and run the installer again: completed steps are skipped."
        lls_echo error "Full log: $LLS_LOG"
    }

    lls_preflight() {
        lls_echo step "== Preflight"

        if [ "$(id -u)" -eq 0 ]; then
            lls_echo error "Run this as your normal user, not as root: the databases and Gash are set up for that user."
            exit 1
        fi
        command -v sudo >/dev/null || { lls_echo error "sudo is required."; exit 1; }
        command -v apt-get >/dev/null || { lls_echo error "apt-get is required (Debian/Ubuntu only)."; exit 1; }

        # shellcheck disable=SC1091
        . /etc/os-release
        LLS_DISTRO="${ID-}"
        LLS_CODENAME="${VERSION_CODENAME-}"
        LLS_RELEASE="$LLS_DISTRO:${VERSION_ID-}"
        case "$LLS_RELEASE" in
            debian:13 | ubuntu:24.04 | ubuntu:26.04) ;;
            *)
                lls_echo error "Unsupported system: ${PRETTY_NAME-unknown}. Supported: Debian 13, Ubuntu 24.04, Ubuntu 26.04."
                exit 1
                ;;
        esac

        if [ "$OPT_WSL" = "auto" ]; then
            if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] || grep -qi microsoft /proc/version 2>/dev/null; then
                OPT_WSL=1
            else
                OPT_WSL=0
            fi
        fi

        lls_echo "System: ${PRETTY_NAME-} ($LLS_CODENAME), user: $USER, WSL tuning: $([ "$OPT_WSL" -eq 1 ] && echo yes || echo no)"
        lls_echo "PHP: $OPT_PHP | MariaDB $LLS_MARIADB_SERIES | PostgreSQL $OPT_PG | shell: $OPT_SHELL"
        lls_echo warning "For development machines only: do not run this on a production server."

        if ! lls_ask "Continue?" y; then
            exit 1
        fi

        sudo true
        # Keep the sudo timestamp fresh for the whole run.
        (while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done) &

        lls_check_ports
    }

    # A port that is listening but has no owner process visible from here belongs to another
    # network namespace: on WSL2 every distro shares one network stack, so a stack running in
    # another distro takes the ports this one needs (services fail, PostgreSQL silently moves to 5433).
    lls_check_ports() {
        local ports="3306 5432 6379" port conflicts=""
        if [ "$OPT_HTE" -eq 1 ] && [ "$OPT_HTE_PORTS" = "standard" ]; then
            ports+=" 80 443"
        fi
        for port in $ports; do
            sudo ss -Hltn "sport = :$port" | grep -q . || continue
            sudo ss -Hltnp "sport = :$port" | grep -q 'users:' && continue
            conflicts+=" $port"
        done
        [ -z "$conflicts" ] && return 0

        lls_echo error "Ports already in use by something outside this system:$conflicts"
        if [ "$OPT_WSL" -eq 1 ]; then
            lls_echo error "All WSL2 distributions share one network: stop the services using these ports in the other distribution"
            lls_echo error "(for example: sudo systemctl stop mariadb postgresql redis-server apache2), then run this installer again."
        else
            lls_echo error "Free these ports, then run this installer again."
        fi
        exit 1
    }

    lls_wsl_tuning() {
        [ "$OPT_WSL" -eq 1 ] || return 0
        lls_echo step "== WSL base tuning"
        local changed=0

        lls_ini_set /etc/wsl.conf boot systemd true && changed=1
        # WSL runs "mount -a" before /mnt/c exists; systemd mounts /etc/fstab itself.
        lls_ini_set /etc/wsl.conf automount mountFsTab false && changed=1
        lls_ini_set /etc/wsl.conf user default "$USER" && changed=1
        # WSL waits 10 s for systemd by default: a slow first boot (tmpfiles cleanup, fsck) then loses the user session.
        # An explicit option wins; otherwise a value already in the file is kept.
        local init_timeout="$OPT_WSL_INIT_TIMEOUT"
        if [ -z "$init_timeout" ]; then
            init_timeout="$(lls_ini_get /etc/wsl.conf boot initTimeout)"
            [ -n "$init_timeout" ] || init_timeout="$LLS_WSL_INIT_TIMEOUT"
        fi
        lls_ini_set /etc/wsl.conf boot initTimeout "$init_timeout" && changed=1
        if [ -n "$OPT_WSL_APPEND_PATH" ]; then
            lls_ini_set /etc/wsl.conf interop appendWindowsPath "$OPT_WSL_APPEND_PATH" && changed=1
        fi

        if [ -d /run/systemd/system ]; then
            # /tmp on tmpfs: a disk /tmp is wiped by systemd-tmpfiles at every boot, which slows WSL boot down.
            if ! systemctl cat tmp.mount >/dev/null 2>&1 && [ -f /usr/share/systemd/tmp.mount ]; then
                sudo cp /usr/share/systemd/tmp.mount /etc/systemd/system/tmp.mount
                changed=1
            fi
            printf '%s\n[Mount]\nOptions=mode=1777,strictatime,nosuid,nodev,size=%s,nr_inodes=1m\n' "$LLS_MANAGED" "$OPT_TMP_SIZE" |
                lls_put_file /etc/systemd/system/tmp.mount.d/size.conf && changed=1

            # systemd sees WSL as a container and skips fstrim: without TRIM the sparse VHDX never shrinks.
            local unit
            for unit in fstrim.timer fstrim.service; do
                printf '%s\n[Unit]\nConditionVirtualization=\n' "$LLS_MANAGED" |
                    lls_put_file "/etc/systemd/system/$unit.d/wsl.conf" && changed=1
            done
            sudo systemctl daemon-reload
            systemctl is-enabled tmp.mount >/dev/null 2>&1 || { sudo systemctl enable tmp.mount; changed=1; }
            systemctl is-enabled fstrim.timer >/dev/null 2>&1 || sudo systemctl enable fstrim.timer
            sudo systemctl start fstrim.timer

            # WSL has no tty1: getty@tty1 only fails and leaves the system "degraded".
            if [ "$(systemctl is-enabled getty@tty1.service 2>/dev/null || true)" != "masked" ]; then
                sudo systemctl mask getty@tty1.service
                sudo systemctl reset-failed getty@tty1.service 2>/dev/null || true
            fi
        else
            # The services below need systemd: stop here, it starts after the WSL restart.
            lls_echo warning "systemd is not running yet. From Windows run  wsl --terminate ${WSL_DISTRO_NAME:-<distro>}"
            lls_echo warning "then reopen the terminal and run this installer again."
            exit 0
        fi

        if [ "$changed" -eq 1 ]; then
            LLS_NEEDS_WSL_RESTART=1
        fi
    }

    lls_base_packages() {
        lls_echo step "== Base packages"
        # A run interrupted inside mariadb_repo_setup can leave the repository without its key, and then
        # every "apt-get update" fails: drop it here, the Repositories step adds it again.
        if [ ! -s /etc/apt/keyrings/mariadb-keyring.gpg ] &&
            { [ -e /etc/apt/sources.list.d/mariadb.sources ] || [ -e /etc/apt/sources.list.d/mariadb.list ]; }; then
            sudo rm -f /etc/apt/sources.list.d/mariadb.sources /etc/apt/sources.list.d/mariadb.list
            lls_echo warning "  removed a MariaDB repository left without its signing key by an earlier run"
        fi
        # Lax retries and timeouts: third-party repos are sometimes slow.
        printf '%s\nAcquire::Retries "20";\nAcquire::https::Timeout "240";\nAcquire::http::Timeout "240";\n' "$LLS_MANAGED" |
            lls_put_file /etc/apt/apt.conf.d/99-lamp-lapp-stack.conf || true
        lls_apt update
        lls_apt upgrade
        lls_apt install ca-certificates curl wget gnupg lsb-release git zip unzip jq openssl postgresql-common
    }

    lls_repositories() {
        lls_echo step "== Repositories"
        local added=0

        # PHP: packages.sury.org for every supported release. The ondrej PPA is being merged into it
        # (Ubuntu 26.04 is served only there); a machine that already uses the PPA keeps it, so the
        # same packages never come from two sources.
        if grep -rqs 'ondrej/php' /etc/apt/sources.list.d/; then
            lls_echo log "  PHP: keeping the existing ppa:ondrej/php"
        else
            if [ ! -f /usr/share/keyrings/debsuryorg-archive-keyring.gpg ]; then
                curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
                sudo dpkg -i /tmp/debsuryorg-archive-keyring.deb
                rm -f /tmp/debsuryorg-archive-keyring.deb
            fi
            echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $LLS_CODENAME main" |
                lls_put_file /etc/apt/sources.list.d/php.list && added=1
        fi

        # PostgreSQL: pgdg, through the helper shipped by postgresql-common.
        if ! grep -rqs 'apt.postgresql.org' /etc/apt/sources.list.d/; then
            sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
            added=1
        fi

        # MariaDB: Debian 13 and Ubuntu 26.04 ship 11.8 LTS; Ubuntu 24.04 ships 10.11, so take 11.8 from mariadb.org there.
        if [ "$LLS_RELEASE" = "ubuntu:24.04" ] && { [ ! -s /etc/apt/keyrings/mariadb-keyring.gpg ] ||
            ! grep -rqs "mariadb-server/$LLS_MARIADB_SERIES/" /etc/apt/sources.list.d/; }; then
            curl -fsSL https://r.mariadb.com/downloads/mariadb_repo_setup |
                sudo bash -s -- --mariadb-server-version="mariadb-$LLS_MARIADB_SERIES" --skip-maxscale --skip-tools
            # mariadb_repo_setup reports a failed key download but still exits 0: check its result.
            if [ ! -s /etc/apt/keyrings/mariadb-keyring.gpg ]; then
                sudo rm -f /etc/apt/sources.list.d/mariadb.sources /etc/apt/sources.list.d/mariadb.list
                lls_echo error "The MariaDB signing key was not installed: the mariadb.org repository was removed again."
                exit 1
            fi
            added=1
        fi

        if [ "$added" -eq 1 ]; then
            lls_apt update
            lls_apt upgrade
        fi
    }

    lls_stack_packages() {
        lls_echo step "== Stack packages"
        local pkgs="apache2 mariadb-server mariadb-client postgresql-$OPT_PG postgresql-client-$OPT_PG redis-server"
        local v m
        for v in $OPT_PHP; do
            for m in $LLS_PHP_MODS; do
                # PHP 8.5 has opcache built in.
                if [ "$m" = "opcache" ] && [ "$v" = "8.5" ]; then
                    continue
                fi
                pkgs+=" php$v-$m"
            done
        done
        # shellcheck disable=SC2086
        lls_apt install $pkgs

        # The newest installed PHP is the default "php".
        local newest
        # shellcheck disable=SC2086
        newest="$(printf '%s\n' $OPT_PHP | sort -V | tail -1)"
        local alt
        for alt in php phar phar.phar; do
            if [ -e "/usr/bin/$alt$newest" ]; then
                sudo update-alternatives --set "$alt" "/usr/bin/$alt$newest" >/dev/null
            fi
        done

        sudo systemctl enable --now redis-server.service mariadb.service postgresql.service
    }

    lls_mariadb() {
        lls_echo step "== MariaDB"
        if {
            echo "$LLS_MANAGED"
            cat <<'EOF'
# Put machine-specific overrides in a file that sorts after this one (e.g. 99-zz-local.cnf).
[mysqld]
bind-address                    = 127.0.0.1
skip-external-locking
skip-name-resolve
max_allowed_packet              = 256M
max_connect_errors              = 1000000
sql_mode                        = NO_ENGINE_SUBSTITUTION
character-set-server            = utf8mb4
collation-server                = utf8mb4_unicode_ci

# === InnoDB ===
default_storage_engine          = InnoDB
innodb_buffer_pool_size         = 1G
innodb_file_per_table           = 1
innodb_flush_log_at_trx_commit  = 0
innodb_flush_method             = O_DIRECT
innodb_log_buffer_size          = 16M
innodb_log_file_size            = 512M
innodb_sort_buffer_size         = 4M
innodb_stats_on_metadata        = 0

# === Connections ===
max_connections                 = 100
back_log                        = 512
thread_cache_size               = 100
interactive_timeout             = 180
wait_timeout                    = 180

# === Buffers and tables ===
key_buffer_size                 = 24M
join_buffer_size                = 4M
read_buffer_size                = 3M
read_rnd_buffer_size            = 4M
sort_buffer_size                = 4M
table_definition_cache          = 40000
table_open_cache                = 40000
open_files_limit                = 60000
max_heap_table_size             = 128M
tmp_table_size                  = 128M

# === Binary log ===
disable_log_bin                 = 1

[mysqldump]
quick
quote_names
max_allowed_packet              = 1024M
EOF
        } | lls_put_file /etc/mysql/mariadb.conf.d/99-custom.cnf; then
            sudo systemctl restart mariadb.service
        fi

        # root keeps unix_socket authentication (sudo mariadb); "default" is the password user for applications.
        local pass_file="$HOME/.mysql-pass" pass
        if [ -f "$pass_file" ] && grep -q '^default:' "$pass_file"; then
            pass="$(grep '^default:' "$pass_file" | head -1 | cut -d: -f2-)"
        else
            pass="$(openssl rand -hex 12)"
            (umask 077; echo "default:$pass" >>"$pass_file")
        fi
        sudo mariadb <<EOF
DELETE FROM mysql.global_priv WHERE User = '';
DROP DATABASE IF EXISTS test;
CREATE USER IF NOT EXISTS 'default'@'localhost' IDENTIFIED BY '$pass';
CREATE USER IF NOT EXISTS 'default'@'127.0.0.1' IDENTIFIED BY '$pass';
ALTER USER 'default'@'localhost' IDENTIFIED BY '$pass';
ALTER USER 'default'@'127.0.0.1' IDENTIFIED BY '$pass';
GRANT ALL ON *.* TO 'default'@'localhost' WITH GRANT OPTION;
GRANT ALL ON *.* TO 'default'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
        chmod 600 "$pass_file"
        lls_echo log "  MariaDB user \"default\": password in $pass_file; root: sudo mariadb"
    }

    lls_postgresql() {
        lls_echo step "== PostgreSQL $OPT_PG"
        local pass_file="$HOME/.pgsql-pass" pass
        if [ -f "$pass_file" ] && grep -q '^default:' "$pass_file"; then
            pass="$(grep '^default:' "$pass_file" | head -1 | cut -d: -f2-)"
        else
            pass="$(openssl rand -hex 12)"
            (umask 077; echo "default:$pass" >>"$pass_file")
        fi
        chmod 600 "$pass_file"

        # "default" is a reserved word in SQL: the role name is always quoted.
        # Your own user gets a superuser role with peer authentication (plain "psql", no password).
        (cd / && sudo -u postgres psql -v ON_ERROR_STOP=1 -q -d postgres) <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'default') THEN
        CREATE ROLE "default" LOGIN SUPERUSER;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$USER') THEN
        CREATE ROLE "$USER" LOGIN SUPERUSER;
    END IF;
END
\$\$;
ALTER ROLE "default" WITH PASSWORD '$pass';
SELECT 'CREATE DATABASE defaultdb OWNER "default"' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'defaultdb')\gexec
SELECT 'CREATE DATABASE "$USER" OWNER "$USER"' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$USER')\gexec
EOF
        lls_echo log "  PostgreSQL role \"default\": password in $pass_file; your role \"$USER\": psql"
    }

    lls_composer() {
        lls_echo step "== Composer"
        local name channel tmp sum
        for name in composer composer1; do
            channel="latest-stable"
            [ "$name" = "composer1" ] && channel="latest-1.x"
            if [ -x "/usr/local/bin/$name" ]; then
                continue
            fi
            tmp="$(mktemp -d)"
            curl -fsSLo "$tmp/composer.phar" "https://getcomposer.org/download/$channel/composer.phar"
            sum="$(curl -fsSL "https://getcomposer.org/download/$channel/composer.phar.sha256sum" | awk '{print $1}')"
            echo "$sum  $tmp/composer.phar" | sha256sum -c --quiet -
            sudo install -m 0755 "$tmp/composer.phar" "/usr/local/bin/$name"
            rm -rf "$tmp"
            lls_echo log "  installed /usr/local/bin/$name"
        done
    }

    lls_gash() {
        [ "$OPT_GASH" -eq 1 ] || return 0
        lls_echo step "== Gash"
        if [ ! -d "$HOME/.gash" ]; then
            if [ "$OPT_SHELL" = gash ]; then
                wget -qO- "$LLS_GASH_INSTALLER" | bash -s -- --assume-yes --quiet
            else
                # Gash as a command only: its installer leaves every shell profile alone.
                wget -qO- "$LLS_GASH_INSTALLER" | PROFILE=/dev/null bash -s -- --assume-yes --quiet
            fi
        else
            lls_echo log "  already installed: update it with \"gash update\""
        fi
        if [ "$OPT_SHELL" != gash ] && [ -x "$HOME/.gash/bin/gash" ]; then
            # The launcher on PATH, so that "gash hte ..." works from any shell.
            mkdir -p "$HOME/.local/bin"
            if [ "$(readlink "$HOME/.local/bin/gash" 2>/dev/null)" != "$HOME/.gash/bin/gash" ]; then
                ln -sfn "$HOME/.gash/bin/gash" "$HOME/.local/bin/gash"
                lls_echo log "  linked ~/.local/bin/gash"
            fi
        fi

        [ "$OPT_HTE" -eq 1 ] || return 0
        local gash_bin
        gash_bin="$(command -v gash || true)"
        [ -n "$gash_bin" ] || gash_bin="$HOME/.gash/bin/gash"
        if [ ! -x "$gash_bin" ]; then
            lls_echo warning "  gash binary not found: open a new shell and run \"gash hte install\""
            return 0
        fi
        # Local sites run as your user through gash hte, not through the system Apache.
        sudo a2dissite -q 000-default >/dev/null 2>&1 || true
        "$gash_bin" hte install --yes --ports "$OPT_HTE_PORTS"

        # gash hte runs its own Apache and PHP-FPM masters: the system ones would only hold memory
        # (~70 MB per PHP version). On ports 80/443 gash hte stops the system Apache itself; on the
        # high ports it leaves it alone, so the installer does it here.
        local v unit units="apache2"
        for v in $OPT_PHP; do units="$units php$v-fpm"; done
        for unit in $units; do
            if systemctl is-enabled --quiet "$unit.service" 2>/dev/null || systemctl is-active --quiet "$unit.service"; then
                sudo systemctl disable --now --quiet "$unit.service"
                lls_echo log "  disabled the system $unit (gash hte runs its own)"
            fi
        done
    }

    lls_node() {
        [ "$OPT_NODE" -eq 1 ] || return 0
        lls_echo step "== nvm + Node LTS"
        export NVM_DIR="$HOME/.nvm"
        if [ ! -s "$NVM_DIR/nvm.sh" ]; then
            wget -qO- "https://raw.githubusercontent.com/nvm-sh/nvm/$LLS_NVM_VERSION/install.sh" | bash
        fi
        # nvm.sh is not written for "set -u".
        set +u
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh"
        nvm install --lts >/dev/null
        set -u
        lls_echo log "  node $(nvm version default 2>/dev/null || nvm current)"
    }

    # Writes stdin as a block between markers at the end of a file of the user, replacing the
    # previous block and keeping every other line.
    lls_user_block() {
        local file="$1" begin="# >>> lamp-lapp-stack >>>" end="# <<< lamp-lapp-stack <<<" tmp
        tmp="$(mktemp)"
        {
            if [ -f "$file" ]; then
                awk -v b="$begin" -v e="$end" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$file"
            fi
            echo "$begin"
            echo "# Managed by lamp-lapp-stack.sh: re-running the installer rewrites this block."
            cat
            echo "$end"
        } >"$tmp"
        if cmp -s "$tmp" "$file"; then
            rm -f "$tmp"
            return 0
        fi
        cat "$tmp" >"$file"
        rm -f "$tmp"
        lls_echo log "  wrote the lamp-lapp-stack block of $file"
    }

    # Removes a block (by default the lamp-lapp-stack one) from a file of the user, if it has one.
    lls_user_block_remove() {
        local file="$1" begin="${2:-# >>> lamp-lapp-stack >>>}" end="${3:-# <<< lamp-lapp-stack <<<}" what="${4:-lamp-lapp-stack}" tmp
        [ -f "$file" ] && grep -qxF "$begin" "$file" || return 0
        tmp="$(mktemp)"
        awk -v b="$begin" -v e="$end" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$file" >"$tmp"
        cat "$tmp" >"$file"
        rm -f "$tmp"
        lls_echo log "  removed the $what block of $file"
    }

    # Writes stdin to a file of the user only when the content differs.
    lls_user_file() {
        local file="$1" tmp
        tmp="$(mktemp)"
        cat >"$tmp"
        if cmp -s "$tmp" "$file"; then
            rm -f "$tmp"
            return 0
        fi
        mkdir -p "$(dirname "$file")"
        cat "$tmp" >"$file"
        rm -f "$tmp"
        lls_echo log "  wrote $file"
    }

    # Makes PATH the login shell, unless the current one is the same program (/bin/bash is /usr/bin/bash).
    lls_login_shell() {
        local want="$1"
        if [ "$(readlink -f "$(getent passwd "$USER" | cut -d: -f7)")" != "$(readlink -f "$want")" ]; then
            sudo chsh -s "$want" "$USER"
            lls_echo log "  login shell of $USER: $want"
        fi
    }

    # The starship prompt: from the distribution when it packages it, otherwise the pinned release.
    lls_starship() {
        if command -v starship >/dev/null; then
            return 0
        fi
        if apt-cache policy starship 2>/dev/null | grep -q 'Candidate: [0-9]'; then
            lls_apt install starship
            return 0
        fi
        local arch sum tmp
        case "$(dpkg --print-architecture)" in
            amd64) arch=x86_64; sum="$LLS_STARSHIP_SHA256_X86_64" ;;
            arm64) arch=aarch64; sum="$LLS_STARSHIP_SHA256_AARCH64" ;;
            *) lls_echo warning "  starship: no release for $(dpkg --print-architecture), the prompt stays as it is"; return 0 ;;
        esac
        tmp="$(mktemp -d)"
        curl -fsSLo "$tmp/starship.tar.gz" \
            "https://github.com/starship/starship/releases/download/v$LLS_STARSHIP_VERSION/starship-$arch-unknown-linux-musl.tar.gz"
        echo "$sum  $tmp/starship.tar.gz" | sha256sum -c --quiet -
        tar -xzf "$tmp/starship.tar.gz" -C "$tmp" starship
        sudo install -m 0755 "$tmp/starship" /usr/local/bin/starship
        rm -rf "$tmp"
        lls_echo log "  installed /usr/local/bin/starship $LLS_STARSHIP_VERSION (SHA-256 checked)"
    }

    lls_shell() {
        lls_echo step "== Shell: $OPT_SHELL"
        local bash_path
        bash_path="$(command -v bash)"
        case "$OPT_SHELL" in
            bash-plus) lls_apt install bash-completion fzf zoxide ;;
            zsh) lls_apt install zsh zsh-autosuggestions zsh-syntax-highlighting fzf zoxide ;;
            fish) lls_apt install fish fzf zoxide ;;
        esac
        case "$OPT_SHELL" in
            bash-plus | zsh | fish) lls_starship ;;
        esac

        # The Gash block of ~/.bashrc (the Gash installer writes it) follows the choice: the gash command stays either way.
        local gash_begin="# >>> GASH START >>>" gash_end="# <<< GASH END <<<"
        if [ "$OPT_SHELL" = gash ]; then
            if [ -f "$HOME/.gashrc" ] && ! grep -qxF "$gash_begin" "$HOME/.bashrc" 2>/dev/null; then
                # The block of the Gash installer, as it writes it.
                # shellcheck disable=SC2016
                printf '\n%s\n# Load Gash Bash - Do not edit this block, it is managed by Gash installer\nif [ -f "$HOME/.gashrc" ]; then\n  source "$HOME/.gashrc"\nfi\n%s\n' \
                    "$gash_begin" "$gash_end" >>"$HOME/.bashrc"
                lls_echo log "  wrote the Gash block of $HOME/.bashrc"
            fi
        else
            lls_user_block_remove "$HOME/.bashrc" "$gash_begin" "$gash_end" Gash
        fi

        # ~/.bashrc carries a block only for bash-plus (the tools) and fish (the hand-over to fish).
        case "$OPT_SHELL" in
            bash-plus)
                # A ~/.inputrc replaces /etc/inputrc, so it includes it first.
                lls_user_file "$HOME/.inputrc" <<'INPUTRC'
# Managed by lamp-lapp-stack.sh (--shell bash-plus): re-running the installer rewrites this file.
$include /etc/inputrc
set completion-ignore-case on
set show-all-if-ambiguous on
set colored-stats on
"\e[A": history-search-backward
"\e[B": history-search-forward
INPUTRC
                lls_user_block "$HOME/.bashrc" <<'BASHRC'
if [[ $- == *i* ]]; then
    shopt -s histappend checkwinsize globstar cdspell
    HISTSIZE=100000
    HISTFILESIZE=200000
    HISTCONTROL=ignoreboth:erasedups
    PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
    # fzf: Ctrl-R history, Ctrl-T files, Alt-C directories ("fzf --bash" exists from 0.48; Ubuntu 24.04 has 0.44).
    if fzf --bash >/dev/null 2>&1; then
        eval "$(fzf --bash)"
    elif [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
        . /usr/share/doc/fzf/examples/key-bindings.bash
    fi
    eval "$(zoxide init bash)"
    eval "$(starship init bash)"
fi
BASHRC
                ;;
            fish)
                # Bash stays the login shell (scripts, IDEs and "sudo -s" expect a POSIX shell): an interactive
                # Bash started by a terminal hands over to fish. "bash" typed inside fish stays Bash.
                lls_user_block "$HOME/.bashrc" <<'BASHRC'
if [[ $- == *i* && -z ${BASH_EXECUTION_STRING-} && $(ps -o comm= -p "$PPID" 2>/dev/null) != fish ]] && command -v fish >/dev/null; then
    shopt -q login_shell && exec fish --login
    exec fish
fi
BASHRC
                ;;
            *) lls_user_block_remove "$HOME/.bashrc" ;;
        esac
        if [ "$OPT_SHELL" != bash-plus ] && [ -f "$HOME/.inputrc" ] && grep -q '^# Managed by lamp-lapp-stack.sh' "$HOME/.inputrc"; then
            rm -f "$HOME/.inputrc"
            lls_echo log "  removed $HOME/.inputrc"
        fi

        case "$OPT_SHELL" in
            zsh)
                # Zsh reads neither ~/.bashrc nor ~/.profile: PATH (the gash launcher) and nvm go here too.
                # Plugins come from the distribution's packages; syntax highlighting must be loaded last.
                lls_user_block "$HOME/.zshrc" <<'ZSHRC'
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE AUTO_CD
mkdir -p ~/.cache/zsh
autoload -Uz compinit && compinit -d ~/.cache/zsh/zcompdump
[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] && . /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
if fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
elif [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
    . /usr/share/doc/fzf/examples/key-bindings.zsh
fi
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && . /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSHRC
                lls_login_shell "$(command -v zsh)"
                ;;
            fish)
                # nvm is a Bash function: "nvm" in fish runs it through Bash and takes the Node it selects onto PATH.
                lls_user_file "$HOME/.config/fish/conf.d/lamp-lapp-stack.fish" <<'FISH'
# Managed by lamp-lapp-stack.sh (--shell fish): re-running the installer rewrites this file.
fish_add_path --global $HOME/.local/bin
set --global --export NVM_DIR $HOME/.nvm

function nvm --description 'nvm, run through Bash'
    set --local bin (bash -c 'source "$NVM_DIR/nvm.sh" --no-use; nvm "$@" >&2 || exit $?; current=$(nvm which current 2>/dev/null) && dirname "$current"' nvm $argv)
    set --local code $status
    if test $code -eq 0; and test -n "$bin"; and test -d "$bin"
        set --local keep
        for dir in $PATH
            string match --quiet -- "$NVM_DIR/*" $dir; or set --append keep $dir
        end
        set --global --export PATH $bin $keep
    end
    return $code
end

if status is-interactive
    if test -s $NVM_DIR/nvm.sh; and not type --query node
        nvm use --silent default >/dev/null 2>&1
    end
    if fzf --fish >/dev/null 2>&1
        fzf --fish | source
    else if functions --query fzf_key_bindings
        fzf_key_bindings
    else if test -f /usr/share/doc/fzf/examples/key-bindings.fish
        source /usr/share/doc/fzf/examples/key-bindings.fish
        fzf_key_bindings
    end
    zoxide init fish | source
    starship init fish | source
end
FISH
                lls_login_shell "$bash_path"
                ;;
            *)
                # Back to Bash when an earlier run had made Zsh the login shell.
                case "$(getent passwd "$USER" | cut -d: -f7)" in
                    */zsh | */fish) lls_login_shell "$bash_path" ;;
                esac
                ;;
        esac
    }

    lls_summary() {
        # "sudo -u postgres" opens a user session whose /run/user cleanup fails on WSL: harmless, but it marks the system "degraded".
        sudo systemctl reset-failed 'user-runtime-dir@*.service' 2>/dev/null || true
        lls_echo info "== Done ($LLS_VERSION)"
        lls_echo "MariaDB: sudo mariadb | user \"default\" in ~/.mysql-pass"
        lls_echo "PostgreSQL $OPT_PG: psql | role \"default\" in ~/.pgsql-pass"
        if [ "$OPT_HTE" -eq 1 ]; then
            lls_echo "Local sites: gash hte site create --domain example.test --docroot public"
        fi
        case "$OPT_SHELL" in
            gash) lls_echo "Shell: Bash with Gash. Open a new terminal, then run: gash" ;;
            bash-plus) lls_echo "Shell: Bash with fzf, zoxide and starship. Open a new terminal." ;;
            zsh) lls_echo "Shell: Zsh with autosuggestions and syntax highlighting. Open a new terminal." ;;
            fish) lls_echo "Shell: Fish in the terminal, Bash for the scripts. Open a new terminal." ;;
            bash) lls_echo "Shell: the distribution's Bash, unchanged" ;;
        esac
        lls_echo "SSH key: none created. See the guide, \"Create your SSH key\"."
        if [ "${LLS_NEEDS_WSL_RESTART-0}" -eq 1 ]; then
            lls_echo warning "WSL settings changed: from Windows run  wsl --terminate ${WSL_DISTRO_NAME:-<distro>}  then reopen the terminal."
        fi
    }

    lls_main() {
        lls_parse_args "$@"
        lls_choose_shell
        # Work from the home directory: helper scripts (mariadb_repo_setup) download into the current
        # directory, and a terminal opened from Windows often starts in /mnt/c, where root cannot write.
        cd "$HOME"
        LLS_LOG="$HOME/.local/state/lamp-lapp-stack/install-$(date +%Y%m%d-%H%M%S).log"
        mkdir -p "$(dirname "$LLS_LOG")"
        exec > >(tee -a "$LLS_LOG") 2>&1
        trap 'lls_on_error $LINENO $?' ERR

        lls_preflight
        lls_wsl_tuning
        lls_base_packages
        lls_repositories
        lls_stack_packages
        lls_mariadb
        lls_postgresql
        lls_composer
        lls_gash
        lls_node
        lls_shell
        lls_summary
    }

    lls_main "$@"

} # this ensures the entire script is downloaded #
