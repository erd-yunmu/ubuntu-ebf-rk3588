#!/bin/bash

set -u

# MAC / CPUID only; board dtb and uEnv are handled by U-Boot.

NET_DIR="/etc/systemd/network"
NET_LINK_PREFIX="10-lubancat"

MAC_IDS_FILE="/etc/mac-lookup/ids.txt"

LOG_FILE=/var/log/board-detect.log

log() {
    echo "$*"
    echo "$*" >> "${LOG_FILE}"
}

llog_prefixed() {
    log "[board-detect] $*"
}

soc_unique_id() {
    local id

    id="$(tr -d '\0' < /proc/device-tree/serial-number 2> /dev/null)"
    [ -n "${id}" ] && echo "${id}" && return 0

    id="$(sed -n 's/^Serial[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo 2> /dev/null | head -n 1)"
    [ -n "${id}" ] && echo "${id}"
}

mac_for_iface() {
    printf '%s:%s' "$1" "$2" | md5sum | cut -c1-10 \
        | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\)$/02:\1:\2:\3:\4:\5/'
}

setup_mac() {
    local id dev iface link mac cur

    id="$(soc_unique_id)"
    [ -n "${id}" ] || return 0

    mkdir -p "${NET_DIR}" 2> /dev/null

    for dev in /sys/class/net/eth*; do
        [ -e "${dev}" ] || continue
        iface="$(basename "${dev}")"
        link="${NET_DIR}/${NET_LINK_PREFIX}-${iface}.link"
        [ -f "${link}" ] && continue
        mac="$(mac_for_iface "${id}" "${iface}")"
        {
            echo "[Match]"
            echo "OriginalName=${iface}"
            echo
            echo "[Link]"
            echo "MACAddress=${mac}"
        } > "${link}"
        cur="$(cat "${dev}/address" 2> /dev/null)"
        if [ "${cur}" != "${mac}" ]; then
            ip link set dev "${iface}" address "${mac}" 2> /dev/null \
                && llog_prefixed "iface ${iface}: MAC set to ${mac} (link file created)"
        fi
    done

    return 0
}

record_cpuid() {
    local id note

    id="$(soc_unique_id)"
    [ -n "${id}" ] || return 0
    if [ ! -f "${MAC_IDS_FILE}" ]; then
        mkdir -p "$(dirname "${MAC_IDS_FILE}")" 2> /dev/null
        printf '# one entry per board:  <cpuid>  <note>\n' > "${MAC_IDS_FILE}" 2> /dev/null
    fi

    grep -q "^${id}[[:space:]]" "${MAC_IDS_FILE}" 2> /dev/null && return 0
    note="$(tr -d '\0' < /proc/device-tree/model 2> /dev/null)"
    printf '%s %s (%s)\n' "${id}" "${note}" "$(hostname 2> /dev/null)" >> "${MAC_IDS_FILE}" 2> /dev/null
}

# Point ubuntuEnv.txt at the board uEnv.
setup_uenv_link() {
    local uenv link target

    uenv="$(tr -d '\0' < /proc/device-tree/chosen/lubancat,uenv 2> /dev/null)"
    [ -n "${uenv}" ] || return 0

    target="uEnv/uEnv-${uenv}.txt"
    link="/boot/firmware/ubuntuEnv.txt"
    [ -e "/boot/firmware/${target}" ] || return 0
    if [ -L "${link}" ] && [ "$(readlink "${link}")" = "${target}" ]; then
        return 0
    fi

    rm -f "${link}"
    ln -s "${target}" "${link}" && llog_prefixed "ubuntuEnv.txt -> ${target}"
    return 0
}

main() {
    { : >> "${LOG_FILE}"; } 2> /dev/null || LOG_FILE=/tmp/board-detect.log

    llog_prefixed "MAC/CPUID setup (board model / dtb handled by U-Boot)"
    setup_mac
    record_cpuid
    setup_uenv_link

    return 0
}

main "$@"
