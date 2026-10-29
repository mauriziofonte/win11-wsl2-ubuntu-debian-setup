# A "plain machine" for lamp-lapp-stack.sh: the distribution image with systemd as PID 1, a user "dev"
# with passwordless sudo (the installer asks once for the sudo password; CI has nobody to type it).
# The image's policy-rc.d, which stops packages from starting their services, goes: a real system has none.
# So does the dpkg filter of the Ubuntu images that drops /usr/share/doc: a real system keeps the fzf
# key bindings that Ubuntu 24.04 ships there.
# Units that touch the kernel or devices are masked: the container runs --privileged on the CI VM.
# systemd-sysctl applies only the low-port key that gash hte installs, so its boot behaviour is real
# without changing the VM's kernel settings.
ARG BASE=mirror.gcr.io/library/debian:13
FROM ${BASE}
ENV DEBIAN_FRONTEND=noninteractive container=docker
RUN apt-get update \
    && apt-get install -y --no-install-recommends systemd systemd-sysv dbus dbus-user-session libpam-systemd \
        sudo iproute2 procps ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/sbin/policy-rc.d \
    && rm -f /etc/dpkg/dpkg.cfg.d/excludes \
    && systemctl mask systemd-udevd.service systemd-udev-trigger.service systemd-modules-load.service \
        systemd-remount-fs.service systemd-firstboot.service systemd-timesyncd.service getty.target \
        console-getty.service systemd-binfmt.service proc-sys-fs-binfmt_misc.automount \
        proc-sys-fs-binfmt_misc.mount kmod-static-nodes.service systemd-random-seed.service \
        sys-kernel-debug.mount sys-kernel-tracing.mount sys-kernel-config.mount \
        sys-fs-fuse-connections.mount dev-hugepages.mount \
    && mkdir -p /etc/systemd/system/systemd-sysctl.service.d \
    && printf '[Service]\nExecStart=\nExecStart=/usr/lib/systemd/systemd-sysctl --prefix=/net/ipv4/ip_unprivileged_port_start\n' \
        >/etc/systemd/system/systemd-sysctl.service.d/only-low-ports.conf \
    && if id -u ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
    && useradd -m -s /bin/bash -G sudo dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev && chmod 0440 /etc/sudoers.d/dev
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
