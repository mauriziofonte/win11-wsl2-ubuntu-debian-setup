#!/usr/bin/env bash
# The check descriptions quote paths and SQL as text (~/..., `default`): no expansion is meant there.
# shellcheck disable=SC2088,SC2016

# Checks, on a machine where lamp-lapp-stack.sh ran, the facts that the guide states about the result.
# Every check names the section of the guide it backs. Run it as the user who ran the installer.
#
#   tests/verify-stack.sh install   # right after the installer; also runs the guide's "first local site"
#   tests/verify-stack.sh reboot    # after the distribution (or container) restarted
#
# The expectations follow the installer's options, passed as environment variables:
#   PHP_VERSIONS   PHP versions installed (default: all, 5.6 to 8.5)
#   PG             PostgreSQL major (default: 18)
#   SHELL_CHOICE   gash, zsh or bash (default: gash)
#   EXPECT_GASH    1 or 0 (default: 1)
#   EXPECT_HTE     1 or 0 (default: EXPECT_GASH)
#   HTE_PORTS      standard or high (default: standard)
#   EXPECT_NODE    1 or 0 (default: 1)
#   EXPECT_WSL     1 or 0: the WSL tuning was applied (default: 1 on WSL, 0 elsewhere)
#   TMP_SIZE       the --tmp-size value (default: 25%)
#   SCOPE          installer (default), or manual: the guide's manual steps 4.2 and 4.3 ran instead of the
#                  installer, so only the packages and the services they install are checked
#
# Output: one "ok" or "not ok" line per check, TAP style; exit status 1 when a check fails.
#
# Author: Maurizio Fonte (https://www.mauriziofonte.it)
# License: MIT License

set -uo pipefail

PHASE="${1:-install}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUIDE="$ROOT/docs/en/SETUP-EN.md"

PHP_ALL="5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3 8.4 8.5"
PHP_VERSIONS="${PHP_VERSIONS:-$PHP_ALL}"
PG="${PG:-18}"
SHELL_CHOICE="${SHELL_CHOICE:-gash}"
EXPECT_GASH="${EXPECT_GASH:-1}"
EXPECT_HTE="${EXPECT_HTE:-$EXPECT_GASH}"
HTE_PORTS="${HTE_PORTS:-standard}"
EXPECT_NODE="${EXPECT_NODE:-1}"
TMP_SIZE="${TMP_SIZE:-25%}"
SCOPE="${SCOPE:-installer}"
ON_WSL=0
if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] || grep -qi microsoft /proc/version 2>/dev/null; then
    ON_WSL=1
fi
EXPECT_WSL="${EXPECT_WSL:-$ON_WSL}"
USER="${USER:-$(id -un)}"
GASH="$HOME/.gash/bin/gash"
# shellcheck disable=SC2086
NEWEST_PHP="$(printf '%s\n' $PHP_VERSIONS | sort -V | tail -1)"
# shellcheck disable=SC2086
OLDEST_PHP="$(printf '%s\n' $PHP_VERSIONS | sort -V | head -1)"
SITE_PORT=""
[ "$HTE_PORTS" = high ] && SITE_PORT=":8443"

COUNT=0
FAILED=0

ok() {
    COUNT=$((COUNT + 1))
    printf 'ok %d - %s\n' "$COUNT" "$1"
}

not_ok() {
    COUNT=$((COUNT + 1))
    FAILED=$((FAILED + 1))
    printf 'not ok %d - %s\n' "$COUNT" "$1"
    if [ -n "${2-}" ]; then
        printf '%s\n' "$2" | sed 's/^/#   /' | head -40
    fi
}

# check "description" command...: the command must succeed.
check() {
    local desc="$1" out
    shift
    if out="$("$@" 2>&1)"; then
        ok "$desc"
    else
        not_ok "$desc" "$out"
    fi
}

# The stdout of a command; its stderr goes to $ERR, shown only when the check fails.
ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT

# check_eq "description" expected command...: the command's output, trimmed, must equal expected.
check_eq() {
    local desc="$1" want="$2" got
    shift 2
    got="$("$@" 2>"$ERR")"
    got="${got%"${got##*[![:space:]]}"}"
    if [ "$got" = "$want" ]; then
        ok "$desc"
    else
        not_ok "$desc" "expected: $want"$'\n'"got:      $got"$'\n'"$(cat "$ERR")"
    fi
}

# check_match "description" regex command...: the command's output must match the extended regex.
check_match() {
    local desc="$1" re="$2" got
    shift 2
    got="$("$@" 2>"$ERR")"
    if printf '%s' "$got" | grep -Eq -- "$re"; then
        ok "$desc"
    else
        not_ok "$desc" "expected to match: $re"$'\n'"got: $got"$'\n'"$(cat "$ERR")"
    fi
}

section() {
    printf '# == %s\n' "$1"
}

# The local addresses a TCP port listens on, one per line.
listen_addrs() {
    sudo ss -Hltn "sport = :$1" | awk '{ print $4 }' | sed 's/:[0-9]*$//' | sort -u
}

only_loopback() {
    local addrs
    addrs="$(listen_addrs "$1")"
    [ -n "$addrs" ] || { echo "nothing listens on $1"; return 1; }
    if printf '%s\n' "$addrs" | grep -Evq '^(127\.0\.0\.1|\[::1\]|\[::ffff:127\.0\.0\.1\])$'; then
        echo "$addrs"
        return 1
    fi
}

unit_state() {
    printf '%s %s' "$(systemctl is-enabled "$1" 2>/dev/null)" "$(systemctl is-active "$1" 2>/dev/null)"
}

# The fenced block that follows "<!-- ci:run NAME -->" in a Markdown file.
doc_block() {
    awk -v marker="<!-- ci:run $2 -->" '
        $0 == marker { armed = 1; next }
        armed && /^```/ { if (inblock) exit; inblock = 1; next }
        inblock { print }
    ' "$1"
}

ini_value() {
    awk -v sec="$2" -v key="$3" '
        /^[[:space:]]*\[/ { insec = ($0 ~ "^[[:space:]]*\\[" sec "\\]") ; next }
        insec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
    ' "$1"
}

php_has_modules() {
    local v="$1" mods missing="" m
    mods="$("php$v" -m 2>/dev/null)"
    for m in bcmath bz2 curl gd gmp igbinary imagick imap intl mbstring mcrypt memcached msgpack mysqli pdo_mysql \
        "Zend OPcache" pgsql pdo_pgsql readline redis soap sqlite3 pdo_sqlite xml xsl zip; do
        printf '%s\n' "$mods" | grep -qxF "$m" || missing+=" [$m]"
    done
    [ -z "$missing" ] || { echo "missing:$missing"; return 1; }
}

php_minor() {
    "$1" -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;' 2>/dev/null
}

site_body() {
    curl -ks --max-time 20 "https://shop.test$SITE_PORT/"
}

# ----------------------------------------------------------------------------------------------
section "System (phase: $PHASE)"
# shellcheck disable=SC1091
. /etc/os-release
check_match "the system is Debian 13, Ubuntu 24.04 or Ubuntu 26.04 (System Requirements)" \
    '^(debian:13|ubuntu:24\.04|ubuntu:26\.04)$' echo "$ID:$VERSION_ID"
check_match "systemd runs as PID 1 (4.1)" '^systemd$' ps -p 1 -o comm=
# Right after a (re)start the services may still be starting: wait for the boot to finish.
state="$(timeout 300 systemctl is-system-running --wait 2>/dev/null)"
printf '# systemd state: %s\n' "$state"
if [ "$state" = degraded ]; then
    systemctl --failed --plain --no-legend --no-pager | sed 's/^/#   failed: /'
fi

# ----------------------------------------------------------------------------------------------
if [ "$EXPECT_WSL" -eq 1 ]; then
    section "WSL tuning (4.1)"
    check_eq "/etc/wsl.conf [boot] systemd=true" true ini_value /etc/wsl.conf boot systemd
    check_eq "/etc/wsl.conf [automount] mountFsTab=false" false ini_value /etc/wsl.conf automount mountFsTab
    check_eq "/etc/wsl.conf [user] default=$USER" "$USER" ini_value /etc/wsl.conf user default
    check_match "tmp.mount caps /tmp at $TMP_SIZE" "size=${TMP_SIZE}," cat /etc/systemd/system/tmp.mount.d/size.conf
    check_match "tmp.mount is enabled" '^(enabled|static|generated|alias)' systemctl is-enabled tmp.mount
    if [ "$PHASE" = reboot ]; then
        check_eq "/tmp is a tmpfs after the restart" tmpfs findmnt -no FSTYPE /tmp
    fi
    for unit in fstrim.timer fstrim.service; do
        check "$unit has the drop-in that clears ConditionVirtualization" \
            grep -qx 'ConditionVirtualization=' "/etc/systemd/system/$unit.d/wsl.conf"
    done
    check_eq "fstrim.timer is enabled and active" "enabled active" unit_state fstrim.timer
    check_eq "getty@tty1.service is masked" masked systemctl is-enabled getty@tty1.service
    check "no getty unit failed" bash -c '! systemctl --failed --plain --no-legend | grep -q getty'
fi

# ----------------------------------------------------------------------------------------------
section "PHP (4.3)"
for v in $PHP_VERSIONS; do
    check_eq "php$v runs PHP $v" "$v" php_minor "php$v"
    check "php$v has the extensions of the guide" php_has_modules "$v"
    check "php-fpm$v is installed" test -x "/usr/sbin/php-fpm$v"
done
check_eq "the default php is the newest installed ($NEWEST_PHP)" "$NEWEST_PHP" php_minor php
case " $PHP_VERSIONS " in
    *" 8.5 "*) check_match "PHP 8.5 has OPcache built in" '^Zend OPcache$' php8.5 -m ;;
esac

# ----------------------------------------------------------------------------------------------
section "Apache"
check_match "Apache 2.4 is installed" 'Apache/2\.4\.' sudo /usr/sbin/apache2ctl -v
if [ "$EXPECT_HTE" -eq 1 ]; then
    check_match "the system Apache is stopped and disabled, gash hte serves the sites (4.7)" \
        '^(disabled|masked) (inactive|failed)' unit_state apache2.service
    for v in $PHP_VERSIONS; do
        check_match "the system php$v-fpm is stopped and disabled (4.7)" \
            '^(disabled|masked) (inactive|failed)' unit_state "php$v-fpm.service"
    done
else
    check_eq "without gash hte the system Apache keeps running" "enabled active" unit_state apache2.service
fi

# ----------------------------------------------------------------------------------------------
section "MariaDB (4.4)"
check_eq "mariadb.service is enabled and active" "enabled active" unit_state mariadb.service
check_match "MariaDB is 11.8" '^11\.8\.' sudo mariadb -NBe 'SELECT VERSION()'
check_eq "root logs in with sudo mariadb (unix socket)" root@localhost sudo mariadb -NBe 'SELECT CURRENT_USER()'
if [ "$SCOPE" = installer ]; then
    check_eq "99-custom.cnf: utf8mb4, utf8mb4_unicode_ci, 127.0.0.1, 1 GB buffer pool, no binlog, NO_ENGINE_SUBSTITUTION" \
        $'utf8mb4\tutf8mb4_unicode_ci\t127.0.0.1\t1073741824\t0\tNO_ENGINE_SUBSTITUTION' \
        sudo mariadb -NBe 'SELECT @@character_set_server, @@collation_server, @@bind_address, @@innodb_buffer_pool_size, @@log_bin, @@sql_mode'
    check "99-custom.cnf carries the managed header" grep -q '^# Managed by lamp-lapp-stack.sh' /etc/mysql/mariadb.conf.d/99-custom.cnf
    check_eq "~/.mysql-pass is readable by you only" 600 stat -c %a "$HOME/.mysql-pass"
    MYSQL_PASS="$(grep '^default:' "$HOME/.mysql-pass" 2>/dev/null | head -1 | cut -d: -f2-)"
    check_eq "user default logs in on 127.0.0.1:3306 with the password of ~/.mysql-pass" "default@127.0.0.1" \
        env MYSQL_PWD="$MYSQL_PASS" mariadb -u default -h 127.0.0.1 -P 3306 -NBe 'SELECT CURRENT_USER()'
    check_eq "user default logs in through the socket too" "default@localhost" \
        env MYSQL_PWD="$MYSQL_PASS" mariadb -u default -NBe 'SELECT CURRENT_USER()'
    check_match "user default has all privileges, with grant option" 'GRANT ALL PRIVILEGES ON \*\.\* TO `default`@`localhost`.*WITH GRANT OPTION' \
        sudo mariadb -NBe 'SHOW GRANTS FOR `default`@`localhost`'
    check_eq "no anonymous users" 0 sudo mariadb -NBe "SELECT COUNT(*) FROM mysql.global_priv WHERE User = ''"
    check_eq "no test database" "" sudo mariadb -NBe "SHOW DATABASES LIKE 'test'"
    check "MariaDB listens on 127.0.0.1 only" only_loopback 3306
fi

# ----------------------------------------------------------------------------------------------
section "PostgreSQL (4.5)"
check_eq "postgresql.service is enabled and active" "enabled active" unit_state postgresql.service
check_match "PostgreSQL is $PG, from pgdg" "^$PG\." bash -c 'cd / && sudo -u postgres psql -XtAc "SHOW server_version"'
check_eq "one cluster only, $PG/main on port 5432" "$PG main 5432" bash -c "pg_lsclusters -h | awk '{ print \$1, \$2, \$3 }'"
check_eq "sudo -u postgres psql works (peer)" 1 bash -c 'cd / && sudo -u postgres psql -XtAc "SELECT 1"'
check "PostgreSQL listens on loopback only" only_loopback 5432
if [ "$SCOPE" = installer ]; then
    check_eq "your role ($USER) is a superuser with its own database, plain psql (peer)" "t|$USER" \
        psql -XtAc 'SELECT rolsuper, current_database() FROM pg_roles WHERE rolname = current_user'
    check_eq "~/.pgsql-pass is readable by you only" 600 stat -c %a "$HOME/.pgsql-pass"
    PGSQL_PASS="$(grep '^default:' "$HOME/.pgsql-pass" 2>/dev/null | head -1 | cut -d: -f2-)"
    check_eq "role \"default\" logs in on 127.0.0.1 with the password of ~/.pgsql-pass, superuser, owns defaultdb" \
        "default|t|default" env PGPASSWORD="$PGSQL_PASS" psql -X -h 127.0.0.1 -U default defaultdb -tAc \
        'SELECT current_user, (SELECT rolsuper FROM pg_roles WHERE rolname = current_user), (SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = current_database())'
fi

# ----------------------------------------------------------------------------------------------
section "Redis"
check_eq "redis-server.service is enabled and active" "enabled active" unit_state redis-server.service
check_eq "redis answers" PONG redis-cli ping
check "Redis listens on loopback only" only_loopback 6379

# ----------------------------------------------------------------------------------------------
if [ "$SCOPE" = installer ]; then
    section "Composer (4.6)"
    check_match "composer is Composer 2" '^Composer version 2\.' bash -c 'composer --version 2>/dev/null | grep "^Composer version"'
    if [ "$(printf '%s\n' "$OLDEST_PHP" 8.0 | sort -V | head -1)" != 8.0 ]; then
        check_match "composer1 is Composer 1 (run with PHP $OLDEST_PHP)" '^Composer version 1\.' \
            bash -c "php$OLDEST_PHP /usr/local/bin/composer1 --version 2>/dev/null | grep '^Composer version'"
    else
        check "composer1 is installed" test -x /usr/local/bin/composer1
    fi
fi

# ----------------------------------------------------------------------------------------------
if [ "$EXPECT_GASH" -eq 1 ]; then
    section "Gash and your shell (4.7)"
    check "gash is installed and answers" "$GASH" version
    case "$SHELL_CHOICE" in
        gash)
            check "~/.bashrc loads Gash" grep -q '>>> GASH START >>>' "$HOME/.bashrc"
            check_match "an interactive Bash has the Gash functions" '^function$' bash -c "bash -ic 'type -t gash_doctor' 2>/dev/null"
            aliases="composer-self-update"
            for v in $PHP_VERSIONS; do
                aliases+=" php${v/./} composer${v/./}"
                case "$v" in 5.6 | 7.0 | 7.1 | 7.2) aliases+=" 1composer${v/./}" ;; esac
            done
            # shellcheck disable=SC2016
            check "an interactive Bash has the PHP aliases ($aliases)" bash -c "bash -ic 'for a in $aliases; do alias \"\$a\" >/dev/null || exit 1; done' 2>/dev/null"
            ;;
        zsh)
            check_eq "the login shell is zsh" "$(command -v zsh)" bash -c "getent passwd '$USER' | cut -d: -f7"
            check "Oh My Zsh is installed" test -d "$HOME/.oh-my-zsh"
            check "~/.bashrc does not load Gash" bash -c "! grep -q '>>> GASH START >>>' '$HOME/.bashrc'"
            check "an interactive zsh finds the gash command" bash -c "zsh -ic 'command -v gash' 2>/dev/null"
            ;;
        bash)
            check "~/.bashrc does not load Gash" bash -c "! grep -q '>>> GASH START >>>' '$HOME/.bashrc'"
            check_eq "~/.local/bin/gash links the launcher" "$HOME/.gash/bin/gash" readlink "$HOME/.local/bin/gash"
            ;;
    esac
else
    section "Without Gash"
    check "Gash is not installed (--no-gash)" test ! -e "$HOME/.gash"
fi

# ----------------------------------------------------------------------------------------------
if [ "$EXPECT_HTE" -eq 1 ]; then
    section "gash hte (4.7, 5)"
    check_eq "linger is on, so the stack starts at boot" Linger=yes loginctl show-user "$USER" -p Linger
    user_unit_state() {
        XDG_RUNTIME_DIR="/run/user/$(id -u)" unit_state_user gash-hte.service
    }
    unit_state_user() {
        printf '%s %s' "$(systemctl --user is-enabled "$1" 2>/dev/null)" "$(systemctl --user is-active "$1" 2>/dev/null)"
    }
    check_eq "the systemd user unit gash-hte.service is enabled and active" "enabled active" user_unit_state
    if [ "$HTE_PORTS" = standard ]; then
        check_match "your user may bind ports 80 and 443 (net.ipv4.ip_unprivileged_port_start = 80)" \
            'net\.ipv4\.ip_unprivileged_port_start *= *80' cat /etc/sysctl.d/50-gash-hte.conf
        check_eq "the setting is in force" 80 sysctl -n net.ipv4.ip_unprivileged_port_start
    else
        check "high ports: no port setting" test ! -e /etc/sysctl.d/50-gash-hte.conf
    fi

    if [ "$PHASE" = install ]; then
        if [ "$HTE_PORTS" = standard ]; then
            block="$(doc_block "$GUIDE" first-site)"
            check "the guide has the \"first local site\" commands" test -n "$block"
            # In your terminal "gash" is a shell function; here the launcher stands in for it.
            check "the guide's \"first local site\" commands run as written" \
                env PATH="$HOME/.gash/bin:$PATH" bash -euo pipefail -c "cd ~ && $block"
        else
            check "a site on the high ports" bash -euo pipefail -c \
                "mkdir -p ~/sites/shop/public && echo '<?php echo \"PHP \", PHP_VERSION, PHP_EOL;' > ~/sites/shop/public/index.php && cd ~/sites/shop && '$GASH' hte site create --domain shop.test --docroot public --php 8.4"
        fi
    fi
    check_match "https://shop.test$SITE_PORT/ answers with PHP 8.4" '^PHP 8\.4\.' site_body
    check_eq "the site speaks HTTP/2" 2 curl -ks --max-time 20 -o /dev/null -w '%{http_version}' "https://shop.test$SITE_PORT/"
    check_match "/etc/hosts names shop.test in the gash hte block" '^127\.0\.0\.1[[:space:]].*shop\.test' \
        sed -n '/# >>> gash hte >>>/,/# <<< gash hte <<</p' /etc/hosts
    cert="$(echo | openssl s_client -connect "127.0.0.1${SITE_PORT:-:443}" -servername shop.test 2>/dev/null | openssl x509 -noout -text -dates 2>/dev/null)"
    check_match "the certificate is self-signed ECDSA" 'id-ecPublicKey' echo "$cert"
    days() {
        local from to
        from="$(printf '%s\n' "$cert" | sed -n 's/^notBefore=//p')"
        to="$(printf '%s\n' "$cert" | sed -n 's/^notAfter=//p')"
        echo $((($(date -d "$to" +%s) - $(date -d "$from" +%s)) / 86400))
    }
    check_match "the certificate is valid for 10 years" '^(365[0-9]|366[0-9])$' days
    https_port="${SITE_PORT:-:443}"
    owner() {
        local pids
        pids="$(sudo ss -Hltnp "sport = $https_port" | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u)"
        [ -n "$pids" ] || { echo "nothing listens on $https_port"; return 1; }
        ps -o user= -p "$(printf '%s\n' "$pids" | paste -sd,)" | sort -u
    }
    check_eq "Apache runs as your user" "$USER" owner
    check "no PHP-FPM master runs as root" bash -c '! pgrep -u root -f "php-fpm: master" >/dev/null'
    check_match "gash hte site list shows the site" 'shop\.test' "$GASH" hte site list
    if [ "$PHASE" = install ]; then
        case " $PHP_VERSIONS " in
            *" 7.4 "*)
                check "gash hte site modify --php 7.4 (5)" "$GASH" hte site modify --domain shop.test --php 7.4
                check_match "the site now runs PHP 7.4" '^PHP 7\.4\.' site_body
                check "back to PHP 8.4" "$GASH" hte site modify --domain shop.test --php 8.4
                ;;
        esac
    fi
    check "gash hte doctor reports no failure" "$GASH" hte doctor

    if [ "$ON_WSL" -eq 1 ]; then
        section "Gash on WSL (5, 7)"
        check_match "gash hte hosts windows prints the line for shop.test" 'shop\.test' "$GASH" hte hosts windows
        check "gash wsl info" "$GASH" wsl info
        check "gash win info reads Windows through interop" "$GASH" win info
        check_match "gash win fix hosts-add shows the elevated command (--dry-run)" 'shop\.test' \
            "$GASH" win fix hosts-add 127.0.0.1 shop.test --dry-run
    fi
fi

# ----------------------------------------------------------------------------------------------
if [ "$EXPECT_NODE" -eq 1 ]; then
    section "nvm and Node (4.8)"
    node_check() {
        set +u
        export NVM_DIR="$HOME/.nvm"
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || return 1
        printf '%s %s %s\n' "$(nvm --version)" "$(nvm current)" "$(nvm version lts/*)"
    }
    check_match "nvm 0.40.8 is installed and the current Node is the LTS" '^0\.40\.8 (v[0-9]+\.[0-9]+\.[0-9]+) \1$' node_check
fi

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -gt 0 ]; then
    printf '# %d of %d checks failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# all %d checks passed\n' "$COUNT"
