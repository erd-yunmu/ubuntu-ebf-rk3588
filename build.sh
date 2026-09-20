#!/bin/bash

set -eE 
trap 'echo Error: in $0 on line $LINENO' ERR

cd "$(dirname -- "$(readlink -f -- "$0")")"

BOARD_CONFIG_FILE="build/.board"

list_boards() {
    local file board
    local boards=()
    for file in config/boards/*.conf; do
        [ -e "${file}" ] || continue
        board="$(basename "${file%.conf}")"
        boards+=("${board}")
    done
    local IFS='|'
    echo "${boards[*]}"
}

config_boards() {
    local file board name arch label index
    local boards=() names=() archs=()
    for file in config/boards/*.conf; do
        [ -e "${file}" ] || continue
        board="$(basename "${file%.conf}")"
        name="$(unset BOARD_NAME; . "${file}" >/dev/null 2>&1; echo "${BOARD_NAME}")"
        arch="$(unset OVERLAY_PREFIX; . "${file}" >/dev/null 2>&1; echo "${OVERLAY_PREFIX}")"
        boards+=("${board}")
        names+=("${name:-${board}}")
        archs+=("${arch}")
    done

    if [ "${#boards[@]}" -eq 0 ]; then
        echo "错误：config/boards 下未找到任何板卡配置"
        exit 1
    fi

    local saved=""
    if [ -f "${BOARD_CONFIG_FILE}" ]; then
        saved="$(<"${BOARD_CONFIG_FILE}")"
    fi

    echo "可选的板卡配置："
    for index in "${!boards[@]}"; do
        if [ -n "${archs[$index]}" ]; then
            label="[${archs[$index]}] ${boards[$index]} (${names[$index]})"
        else
            label="${boards[$index]} (${names[$index]})"
        fi
        if [ "${boards[$index]}" == "${saved}" ]; then
            printf '  %d) %s *\n' "$((index + 1))" "${label}"
        else
            printf '  %d) %s\n' "$((index + 1))" "${label}"
        fi
    done

    local choice
    while true; do
        read -r -p "请选择板卡 [1-${#boards[@]}] (q/exit 退出): " choice || exit 0
        case "${choice}" in
            q|Q|exit|quit)
                echo "已取消"
                exit 0
                ;;
        esac
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#boards[@]}" ]; then
            break
        fi
        echo "选择无效，请输入 1 到 ${#boards[@]} 之间的数字"
    done

    mkdir -p "$(dirname -- "${BOARD_CONFIG_FILE}")"
    printf '%s\n' "${boards[$((choice - 1))]}" > "${BOARD_CONFIG_FILE}"
    echo "已保存板卡: ${boards[$((choice - 1))]} (${names[$((choice - 1))]})"
}

load_board() {
    unset BOARD_NAME
    for file in config/boards/*; do
        if [ "${BOARD}" == "$(basename "${file%.conf}")" ]; then
            # shellcheck source=/dev/null
            set -o allexport && source "${file}" && set +o allexport
        fi
    done

    if [[ -z ${BOARD_NAME} ]]; then
        echo "Error: \"${BOARD}\" is an unsupported board"
        echo "Available boards: $(list_boards)"
        exit 1
    fi
}

build_board() {
    # Build the Linux kernel if not found
    if [[ ! -e "$(find build/linux-image-*.deb | sort | tail -n1)" || ! -e "$(find build/linux-headers-*.deb | sort | tail -n1)" ]]; then
        eval "${DOCKER}" ./scripts/build-kernel.sh
    fi

    # Build U-Boot if not found
    if [[ ! -e "$(find build/u-boot-"${BOARD}"_*.deb | sort | tail -n1)" ]]; then
        eval "${DOCKER}" ./scripts/build-u-boot.sh
    fi

    # Create the root filesystem
    eval "${DOCKER}" ./scripts/build-rootfs.sh

    # Create the disk image
    eval "${DOCKER}" ./scripts/config-image.sh
}

usage() {
cat << HEREDOC
Usage: $0 board [$(list_boards)]
       $0 config
       $0 all|clean|kernel|uboot

Commands:
  board, -b BOARD            target board, one of: $(list_boards)
  config                     list boards and save the selected board
  all                        build everything with the saved board
  clean, -c                  remove the build directory
  kernel, -k                 only compile the kernel
  uboot, -u                  only compile uboot
  help, -h                   show this help message and exit
  server, -so                only build server image
  desktop, -do               only build desktop image
HEREDOC
}

if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

cd "$(dirname -- "$(readlink -f -- "$0")")"

for i in "$@"; do
    case $i in
        help)         i="-h" ;;
        board)        i="-b" ;;
        clean)        i="-c" ;;
        kernel)       i="-k" ;;
        uboot|u-boot) i="-u" ;;
        server)       i="-so" ;;
        desktop)      i="-do" ;;
        i)            I_WORD=Y ;;
        love)         LOVE_WORD=Y ;;
        embedfire)    EMBEDFIRE_WORD=Y ;;
    esac

    case $i in
        -h|--help)
            usage
            exit 0
            ;;
        -b=*|--board=*)
            export BOARD="${i#*=}"
            shift
            ;;
        -b|--board)
            export BOARD="${2}"
            shift
            ;;
        config)
            CONFIG_MODE=Y
            ;;
        all)
            BUILD_ALL=Y
            ;;
        -k|--kernel-only)
            export KERNEL_ONLY=Y
            shift
            ;;
        -u|--uboot-only)
            export UBOOT_ONLY=Y
            shift
            ;;
        -do|--desktop-only)
            export DESKTOP_ONLY=Y
            shift
            ;;
        -so|--server-only)
            export SERVER_ONLY=Y
            shift
            ;;
        -c|--clean)
            export CLEAN=Y
            ;;
        -*)
            echo "Error: unknown argument \"$i\""
            exit 1
            ;;
        *)
            ;;
    esac
done

if [[ ${I_WORD} == "Y" && ${LOVE_WORD} == "Y" && ${EMBEDFIRE_WORD} == "Y" ]]; then
    ALL_BOARDS=Y
fi

# List boards and save the selected one
if [[ ${CONFIG_MODE} == "Y" ]]; then
    config_boards
    exit 0
fi

# Build every board in sequence
if [[ ${ALL_BOARDS} == "Y" ]]; then
    mkdir -p build/logs && exec > >(tee "build/logs/build-$(date +"%Y%m%d%H%M%S").log") 2>&1

    IFS='|' read -r -a targets <<< "$(list_boards)"
    for BOARD in "${targets[@]}"; do
        export BOARD
        load_board
        echo "===== ${BOARD_NAME} (${BOARD}) ====="
        build_board
    done
    exit 0
fi

# Use the saved board when no board is passed
if [[ -z ${BOARD} && -f ${BOARD_CONFIG_FILE} ]]; then
    BOARD="$(<"${BOARD_CONFIG_FILE}")"
    export BOARD
fi

# Clean the build directory then exit
if [[ ${CLEAN} == "Y" ]]; then
    if [ -d build/rootfs ]; then
        umount -lf build/rootfs/dev/pts 2> /dev/null || true
        umount -lf build/rootfs/* 2> /dev/null || true
    fi
    rm -rf build
    if [ -n "${BOARD}" ]; then
        mkdir -p build
        printf '%s\n' "${BOARD}" > "${BOARD_CONFIG_FILE}"
    fi
    echo "Removed build"
    exit 0
fi

# No board param passed
if [[ -z ${BOARD} ]]; then
    echo "错误：尚未配置目标板，请先执行: sudo ./build.sh config"
    exit 1
fi

load_board

# Start logging the build process
mkdir -p build/logs && exec > >(tee "build/logs/build-$(date +"%Y%m%d%H%M%S").log") 2>&1

# Build only the Linux kernel then exit
if [[ ${KERNEL_ONLY} == "Y" ]]; then
    eval "${DOCKER}" ./scripts/build-kernel.sh
    exit 0
fi

# Build only U-Boot then exit
if [[ ${UBOOT_ONLY} == "Y" ]]; then
    eval "${DOCKER}" ./scripts/build-u-boot.sh
    exit 0
fi

build_board

exit 0
