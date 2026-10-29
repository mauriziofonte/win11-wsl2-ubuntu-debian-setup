#!/usr/bin/env bash

# Runs lamp-lapp-stack.sh on a plain machine (a container with systemd as PID 1) the way the guide
# says, and checks the result with tests/verify-stack.sh:
#
#   1. a port of the stack held from another network namespace: the installer stops and says so
#   2. curl ... | bash -s -- OPTIONS, as the user "dev"
#   3. verify-stack.sh install
#   4. the installer again: it must change nothing
#   5. the container restarts (a reboot), then verify-stack.sh reboot
#
#   tests/container/run.sh IMAGE SCENARIO      # e.g. mirror.gcr.io/library/debian:13 minimal
#
# The "manual" scenario runs the guide's manual steps instead (the blocks of sections 4.2 and 4.3,
# as written), then verify-stack.sh with SCOPE=manual.
#
# Scenarios (the options they pass):
#   minimal    --php 8.3 --no-gash --no-node
#   zsh        --php "8.4 7.4" --shell zsh --hte-ports high --wsl --tmp-size 2G --wsl-init-timeout 45000
#   bash-plus  --php "8.4 5.6" --shell bash-plus --no-node
#   fish       --php 8.4 --shell fish
#   full       (no options: every PHP version, Gash, gash hte, nvm)
#
# LOG_DIR (default: a new temporary directory) receives the logs of every step.
#
# Author: Maurizio Fonte (https://www.mauriziofonte.it)
# License: MIT License

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
image="${1:?usage: $0 IMAGE SCENARIO}"
scenario="${2:?usage: $0 IMAGE SCENARIO}"
busybox="${BUSYBOX_IMAGE:-mirror.gcr.io/library/busybox:1.37}"
LOG_DIR="${LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG_DIR"

case "$scenario" in
    minimal)
        options=(--php 8.3 --no-gash --no-node)
        expect=(PHP_VERSIONS=8.3 EXPECT_GASH=0 EXPECT_NODE=0 SHELL_CHOICE=bash)
        ;;
    zsh)
        options=(--php "8.4 7.4" --shell zsh --hte-ports high --wsl --tmp-size 2G --wsl-init-timeout 45000)
        expect=("PHP_VERSIONS=8.4 7.4" SHELL_CHOICE=zsh HTE_PORTS=high EXPECT_WSL=1 TMP_SIZE=2G WSL_INIT_TIMEOUT=45000)
        ;;
    bash-plus)
        options=(--php "8.4 5.6" --shell bash-plus --no-node)
        expect=("PHP_VERSIONS=8.4 5.6" SHELL_CHOICE=bash-plus EXPECT_NODE=0)
        ;;
    fish)
        options=(--php 8.4 --shell fish)
        expect=(PHP_VERSIONS=8.4 SHELL_CHOICE=fish)
        ;;
    full)
        options=()
        expect=()
        ;;
    manual)
        options=()
        expect=(SCOPE=manual "PHP_VERSIONS=8.5 8.4" EXPECT_GASH=0 EXPECT_NODE=0 EXPECT_WSL=0)
        ;;
    *)
        echo "unknown scenario: $scenario" >&2
        exit 2
        ;;
esac

tag="lls-test:$(basename "$image" | tr ':' '-')"
name="lls-test-$$"
quoted() {
    [ $# -gt 0 ] && printf ' %q' "$@"
    return 0
}
installer="cat /src/install/lamp-lapp-stack.sh | bash -s -- --yes$(quoted "${options[@]}")"
verify="env$(quoted "${expect[@]}") bash /src/tests/verify-stack.sh"

step() {
    printf '\n\033[1;94m== %s\033[0m\n' "$*"
}

cleanup() {
    docker exec "$name" journalctl -b --no-pager >"$LOG_DIR/journal.log" 2>&1 || true
    docker exec "$name" sh -c 'cat /home/dev/.local/state/lamp-lapp-stack/*.log' >"$LOG_DIR/installer-logs.log" 2>&1 || true
    docker rm -f "$name" "$name-blocker" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_boot() {
    local state=""
    for _ in $(seq 300); do
        state="$(docker exec "$name" systemctl is-system-running 2>/dev/null || true)"
        case "$state" in
            running | degraded) break ;;
        esac
        sleep 0.5
    done
    echo "systemd: $state"
    if [ "$state" = degraded ]; then
        docker exec "$name" systemctl --failed --no-pager || true
    fi
}

# A login session of "dev" (pam_systemd: XDG_RUNTIME_DIR and the user manager), as in a terminal.
as_dev() {
    docker exec "$name" su -l dev -c "$1"
}

step "Image $image ($scenario)"
docker build -q --build-arg BASE="$image" -t "$tag" "$here"
docker run -d --name "$name" --hostname devbox --privileged --cgroupns=private \
    --tmpfs /run --tmpfs /run/lock --sysctl net.ipv4.ip_unprivileged_port_start=1024 \
    -v "$root:/src:ro" "$tag" >/dev/null
wait_boot

if [ "$scenario" = manual ]; then
    # The fenced block after "<!-- ci:run NAME -->" in the English guide.
    doc_block() {
        awk -v marker="<!-- ci:run $1 -->" '
            $0 == marker { armed = 1; next }
            armed && /^```/ { if (inblock) exit; inblock = 1; next }
            inblock { print }
        ' "$root/docs/en/SETUP-EN.md"
    }
    blocks="repositories php-packages stack-packages"
    case "$image" in
        *ubuntu:24.04) blocks="repositories mariadb-repository php-packages stack-packages" ;;
    esac
    n=0
    for block in $blocks; do
        n=$((n + 1))
        step "$n. The guide's manual steps: $block"
        code="$(doc_block "$block")"
        [ -n "$code" ] || { echo "FAIL: no ci:run block named $block in the guide" >&2; exit 1; }
        printf '%s\n' "$code"
        as_dev "cd ~ && bash -euo pipefail -c $(printf '%q' "$code")" 2>&1 | tee "$LOG_DIR/$n-$block.log"
    done
    step "Verify"
    as_dev "$verify install" 2>&1 | tee "$LOG_DIR/verify.log"
    step "Passed: $image ($scenario)"
    exit 0
fi

step "1. Port 3306 held from another network namespace: the installer must stop"
docker run -d --name "$name-blocker" --network "container:$name" "$busybox" httpd -f -p 3306 >/dev/null
sleep 1
rc=0
as_dev "$installer" >"$LOG_DIR/1-conflict.log" 2>&1 || rc=$?
cat "$LOG_DIR/1-conflict.log"
docker rm -f "$name-blocker" >/dev/null
if [ "$rc" -ne 1 ] || ! grep -q 'Ports already in use by something outside this system: 3306' "$LOG_DIR/1-conflict.log"; then
    echo "FAIL: expected exit status 1 and the port message, got status $rc" >&2
    exit 1
fi
echo "ok: the installer stopped (status 1) and named port 3306"

step "2. Install: $installer"
as_dev "$installer" 2>&1 | tee "$LOG_DIR/2-install.log"

step "3. Verify"
as_dev "$verify install" 2>&1 | tee "$LOG_DIR/3-verify.log"

step "4. Run the installer again: nothing may change"
as_dev "$installer" 2>&1 | tee "$LOG_DIR/4-rerun.log"
# The installer reports each change on a line of its own ("  wrote FILE", "  linked ..."), colored.
if grep -aP '^(\x1b\[[0-9;]*m)?  (wrote|linked|installed|disabled|removed) ' "$LOG_DIR/4-rerun.log"; then
    echo "FAIL: the second run changed the lines above" >&2
    exit 1
fi
echo "ok: the second run changed nothing"

step "5. Restart, then verify again"
docker restart "$name" >/dev/null
wait_boot
as_dev "$verify reboot" 2>&1 | tee "$LOG_DIR/5-verify-reboot.log"

step "Passed: $image ($scenario)"
