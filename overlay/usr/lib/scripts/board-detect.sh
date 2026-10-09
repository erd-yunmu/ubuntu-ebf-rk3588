#!/bin/bash

set -u

MODE="${BOARD_DETECT_MODE:-apply}"

ADC_CH_HIGH=2
ADC_CH_LOW=3

ADC_INDEX_10BIT=(229 344 460 595 732 858 975 1024)
ADC_INDEX_12BIT=(916 1376 1840 2380 2928 3432 3900 4096)

BOOT_DIR="/boot/firmware"
ENV_FILE="${BOOT_DIR}/ubuntuEnv.txt"
UENV_DIR="${BOOT_DIR}/uEnv"
DTB_DIR="${BOOT_DIR}/dtbs/rockchip"
LINK_FILE="${DTB_DIR}/rk-kernel.dtb"
DONE_FLAG="${BOOT_DIR}/board-detect.done"

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

dt_compatible() {
    { tr '\0' '\n' < /proc/device-tree/compatible; } 2> /dev/null | sed '/^$/d'
}

find_adc_device() {
    local dev
    for dev in /sys/bus/iio/devices/iio:device*; do
        [ -r "${dev}/name" ] || continue
        if grep -qi "saradc" "${dev}/name" && [ -r "${dev}/in_voltage${ADC_CH_LOW}_raw" ]; then
            echo "${dev}"
            return 0
        fi
    done
    for dev in /sys/bus/iio/devices/iio:device*; do
        if [ -r "${dev}/in_voltage${ADC_CH_LOW}_raw" ]; then
            echo "${dev}"
            return 0
        fi
    done
    return 1
}

adc_to_index() {
    local raw="$1" scale_int="$2" i
    local -a table

    if [ "${scale_int}" -gt 1 ]; then
        table=("${ADC_INDEX_10BIT[@]}")
    else
        table=("${ADC_INDEX_12BIT[@]}")
    fi

    for i in 0 1 2 3 4 5 6 7; do
        if [ "${raw}" -lt "${table[${i}]}" ]; then
            printf '%02d' "${i}"
            return 0
        fi
    done

    printf 'ff'
}

board_lookup() {
    case "$1:$2" in
        rk3576:0000)  echo "LubanCat-3|rk3576-lubancat-3.dtb|lubancat-3" ;;
        rk3576:0001)  echo "LubanCat-3IO|rk3576-lubancat-3io.dtb|lubancat-3io" ;;
        rk3588:0101)  echo "LubanCat-4|rk3588s-lubancat-4-v1.dtb|lubancat-4" ;;
        rk3588:0102)  echo "LubanCat-4 v1|rk3588s-lubancat-4-v1.dtb|lubancat-4" ;;
        rk3588:0201)  echo "LubanCat-4IOF|rk3588s-lubancat-4io.dtb|lubancat-4io" ;;
        rk3588:0301)  echo "LubanCat-4IOB|rk3588s-lubancat-4io.dtb|lubancat-4io" ;;
        rk3588:0401)  echo "LubanCat-5|rk3588-lubancat-5.dtb|lubancat-5" ;;
        rk3588:0402)  echo "LubanCat-5 v2|rk3588-lubancat-5-v2.dtb|lubancat-5-v2" ;;
        rk3588:0501)  echo "LubanCat-5IOF|rk3588-lubancat-5io.dtb|lubancat-5io" ;;
        rk3588:0601)  echo "LubanCat-5IOB|rk3588-lubancat-5io.dtb|lubancat-5io" ;;
        rk3588:0701)  echo "LubanCat-5IOBI|rk3588-lubancat-5io.dtb|lubancat-5io" ;;
        rk3588:0001)  echo "LubanCat-5IOFI|rk3588-lubancat-5io.dtb|lubancat-5io" ;;
        *)            echo "" ;;
    esac
}

getenv_val() {
    sed -n "s/^$1=//p" "${ENV_FILE}" 2> /dev/null | head -n 1
}

apply_env() {
    local dtb="$1" board_env="$2" board_name="$3" board_soc="$4"
    local src_dtb="${DTB_DIR}/${dtb}"
    local src_uenv="${UENV_DIR}/uEnv-${board_env}.txt"
    local board_menu="" cur_fdtfile overlays_want overlays_now
    local fmt_b="N" use_link="N" new_fdtfile link_now need=0

    if [ ! -f "${ENV_FILE}" ]; then
        llog_prefixed "错误: 找不到 ${ENV_FILE}，跳过配置"
        return 1
    fi
    if [ ! -f "${src_dtb}" ]; then
        llog_prefixed "错误: 启动分区里没有设备树 ${dtb}，跳过配置"
        return 1
    fi
    if [ ! -f "${src_uenv}" ]; then
        llog_prefixed "错误: 找不到板级配置 ${src_uenv}，跳过配置"
        return 1
    fi
    if ! grep -q '^fdtfile=' "${ENV_FILE}"; then
        llog_prefixed "错误: ${ENV_FILE} 里没有 fdtfile=，跳过配置"
        return 1
    fi

    cur_fdtfile="$(getenv_val fdtfile)"

    if grep -q '^overlays=' "${ENV_FILE}"; then
        fmt_b="Y"
        overlays_want="$(tr -d '\r' < "${src_uenv}" \
            | sed -e 's/#.*//' \
            | sed -n -e 's|^[[:space:]]*dtoverlay=[[:space:]]*||p' \
            | sed -e 's|[[:space:]]*$||' -e 's|.*/||' -e 's|\.dtbo$||' \
            | grep -v '^$' | awk '!seen[$0]++' | tr '\n' ' ')"
        overlays_want="${overlays_want% }"
        board_menu="$(grep -vE '^[[:space:]]*(#|$)' "${src_uenv}" \
            | grep -v '^[[:space:]]*dtoverlay=')"
        overlays_now="$(getenv_val overlays)"
        [ "${overlays_now}" = "${overlays_want}" ] || need=1
    else
        board_menu="$(cat "${src_uenv}")"
    fi

    if [ "${cur_fdtfile}" = "rk-kernel.dtb" ]; then
        use_link="Y"
        new_fdtfile="rk-kernel.dtb"
        link_now="$(readlink "${LINK_FILE}" 2> /dev/null)"
        [ "${link_now}" = "${dtb}" ] || need=1
    else
        new_fdtfile="${dtb}"
        [ "${cur_fdtfile}" = "${dtb}" ] || need=1
    fi

    if [ "${need}" = "0" ]; then
        llog_prefixed "当前配置已是目标（fdtfile=${new_fdtfile}$([ "${use_link}" = "Y" ] && echo " -> ${dtb}")），无需切换"
        echo "${board_name} ${dtb}" > "${DONE_FLAG}"
        return 0
    fi

    if [ "${use_link}" = "Y" ]; then
        if ! ln -sf "${dtb}" "${LINK_FILE}"; then
            llog_prefixed "错误: 创建软链接 ${LINK_FILE} 失败，跳过配置"
            return 1
        fi
        llog_prefixed "软链接已更新: ${LINK_FILE} -> ${dtb}"
    fi

    {
        sed '/^fdtfile=/,$d' "${ENV_FILE}"
        echo "fdtfile=${new_fdtfile}"
        echo "overlay_prefix=${board_soc}"
        if [ "${fmt_b}" = "Y" ]; then
            echo "overlays=${overlays_want}"
        fi
        if [ -n "${board_menu}" ]; then
            echo "${board_menu}"
        fi
        :
    } > "${ENV_FILE}.new" || {
        llog_prefixed "错误: 生成新配置失败"
        rm -f "${ENV_FILE}.new"
        return 1
    }

    mv "${ENV_FILE}.new" "${ENV_FILE}"
    sync
    echo "${board_name} ${dtb}" > "${DONE_FLAG}"

    llog_prefixed "已更新 fdtfile=${new_fdtfile}$([ "${use_link}" = "Y" ] && echo " (软链接 -> ${dtb})")，板级配置=uEnv-${board_env}.txt"
    llog_prefixed "标记: ${DONE_FLAG}"

    if [ "${MODE}" = "apply" ]; then
        local up
        up="$(cut -d. -f1 /proc/uptime 2> /dev/null)"
        case "${up}" in
            '' | *[!0-9]*) up=25 ;;
        esac
        if [ "${up}" -lt 25 ]; then
            llog_prefixed "等待驱动探测结束再重启（已运行 ${up}s / 25s）"
            sleep $((25 - up))
        fi
        sync
        llog_prefixed "设备树切换完成，重启生效"
        reboot
    fi

    return 0
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
    local id dev iface link mac

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

    if [ -n "${1:-}" ]; then
        if grep -q "^${id}[[:space:]]" "${MAC_IDS_FILE}" 2> /dev/null; then
            sed -i "s|^${id}[[:space:]].*|${id} $1 ($(hostname 2> /dev/null))|" "${MAC_IDS_FILE}" 2> /dev/null
        else
            printf '%s %s (%s)\n' "${id}" "$1" "$(hostname 2> /dev/null)" >> "${MAC_IDS_FILE}" 2> /dev/null
        fi
        return 0
    fi

    grep -q "^${id}[[:space:]]" "${MAC_IDS_FILE}" 2> /dev/null && return 0
    note="$(tr -d '\0' < /proc/device-tree/model 2> /dev/null)"
    printf '%s %s (%s)\n' "${id}" "${note}" "$(hostname 2> /dev/null)" >> "${MAC_IDS_FILE}" 2> /dev/null
}

main() {
    { : >> "${LOG_FILE}"; } 2> /dev/null || LOG_FILE=/tmp/board-detect.log

    local model soc board_compat dev scale scale_int ch raw
    local id_high id_low board_id guess

    if [ "${MODE}" = "apply" ]; then
        setup_mac
        record_cpuid
    fi

    if [ "${MODE}" = "apply" ] && [ -f "${DONE_FLAG}" ]; then
        llog_prefixed "已完成初始化（$(cat "${DONE_FLAG}")），跳过"
        return 0
    fi

    llog_prefixed "===== 板卡识别（模式: ${MODE}）====="
    llog_prefixed "时间: $(date '+%Y-%m-%d %H:%M:%S')"

    model="$({ tr -d '\0' < /proc/device-tree/model; } 2> /dev/null)"
    soc="$(dt_compatible | tail -n 1 | cut -d, -f 2)"
    board_compat="$(dt_compatible | head -n 1)"
    llog_prefixed "当前设备树型号: ${model}"
    llog_prefixed "compatible: $(dt_compatible | tr '\n' ' ')"
    llog_prefixed "SoC: ${soc:-未知}   板卡 compatible: ${board_compat:-未知}"

    if ! dev="$(find_adc_device)"; then
        llog_prefixed "错误: 未找到 SARADC 的 IIO 设备，无法识别板卡"
        return 0
    fi

    scale="$(cat "${dev}/in_voltage_scale" 2> /dev/null)"
    scale_int="${scale%%.*}"
    [ -n "${scale_int}" ] || scale_int=0
    llog_prefixed "IIO 设备: ${dev} (name=$(cat "${dev}/name" 2> /dev/null))"
    llog_prefixed "in_voltage_scale: ${scale}  → 使用 $([ "${scale_int}" -gt 1 ] && echo "10bit(3.3V)" || echo "12bit(1.8V)") 阈值表"

    for ch in 0 1 2 3 4 5 6 7; do
        raw="$(cat "${dev}/in_voltage${ch}_raw" 2> /dev/null)"
        [ -n "${raw}" ] || continue
        llog_prefixed "  ch${ch}: raw=${raw}  index=$(adc_to_index "${raw}" "${scale_int}")"
    done

    raw="$(cat "${dev}/in_voltage${ADC_CH_HIGH}_raw" 2> /dev/null)"
    if [ -z "${raw}" ]; then
        llog_prefixed "错误: 通道 ${ADC_CH_HIGH} 读取失败，无法得到板卡 ID"
        return 0
    fi
    id_high="$(adc_to_index "${raw}" "${scale_int}")"

    raw="$(cat "${dev}/in_voltage${ADC_CH_LOW}_raw" 2> /dev/null)"
    if [ -z "${raw}" ]; then
        llog_prefixed "错误: 通道 ${ADC_CH_LOW} 读取失败，无法得到板卡 ID"
        return 0
    fi
    id_low="$(adc_to_index "${raw}" "${scale_int}")"

    board_id="${id_high}${id_low}"
    llog_prefixed "板卡 ID: ${board_id}  (ch${ADC_CH_HIGH}=${id_high}, ch${ADC_CH_LOW}=${id_low})"

    if [ "${id_high}" = "ff" ] || [ "${id_low}" = "ff" ]; then
        llog_prefixed "提示: ID 超出量程，请检查 ADC 接线或阈值表"
        return 0
    fi

    guess="$(board_lookup "${soc}" "${board_id}")"
    if [ -z "${guess}" ]; then
        llog_prefixed "对应型号: 无匹配，保持当前设备树不动作"
        return 0
    fi

    local board_name="${guess%%|*}"
    local rest="${guess#*|}"
    local dtb="${rest%%|*}"
    local board_env="${rest##*|}"
    llog_prefixed "对应型号（LubanCat 官方映射）: ${board_name} / ${dtb}"

    if [ "${MODE}" = "apply" ]; then
        record_cpuid "${board_name}"
    fi

    if [ "${MODE}" = "learn" ]; then
        llog_prefixed "学习模式：未做任何修改，结果见 ${LOG_FILE}"
        return 0
    fi

    apply_env "${dtb}" "${board_env}" "${board_name}" "${soc}"

    return 0
}

main "$@"
