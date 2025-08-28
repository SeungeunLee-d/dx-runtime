#!/bin/bash
SCRIPT_DIR=$(realpath "$(dirname "$0")")
PROJECT_ROOT=$(realpath "$SCRIPT_DIR")
RUNTIME_PATH=$(realpath -s "${SCRIPT_DIR}")
RT_PATH="${RUNTIME_PATH}/dx_rt"
DRIVER_PATH="${SCRIPT_DIR}/dx_rt_npu_linux_driver"

# Default VENV_PATH, can be overridden by --venv_path option
VENV_PATH_DEFAULT="${RUNTIME_PATH}/venv-dx-runtime"
VENV_PATH="${VENV_PATH_DEFAULT}" # Initialize with default

ENABLE_DEBUG_LOGS=0

# Global variables for script configuration
MIN_PY_VERSION="3.8.10"

# color env settings
source ${PROJECT_ROOT}/scripts/color_env.sh
source ${PROJECT_ROOT}/scripts/common_util.sh

show_help() {
    echo -e "Usage: ${COLOR_CYAN}$(basename "$0") [OPTIONS]${COLOR_RESET}"
    echo -e ""
    echo -e "Options:"
    echo -e "  ${COLOR_GREEN}--all${COLOR_RESET}                              Install all dx-runtime modules"
    echo -e "  ${COLOR_GREEN}--exclude-fw${COLOR_RESET}                       Install all dx-runtime modules except dx_fw"
    echo -e "  ${COLOR_GREEN}--target=<module_name>${COLOR_RESET}             Install specify target dx-runtime module"
    echo -e "                                     (ex> dx_fw | dx_rt_npu_linux_driver | dx_rt | dx_app | dx_stream)"
    echo -e ""
    echo -e "  ${COLOR_GREEN}[--use-ort=<y|n>]${COLOR_RESET}                  Set 'USE_ORT' build option to 'ON or OFF' (default: y)"
    # echo -e "  ${COLOR_GREEN}[--sanity-check=<y|n>]${COLOR_RESET}             Turn SanityCheck ON or OFF for dx_rt (default: y)"
    echo -e "  ${COLOR_GREEN}[--driver-source-build]${COLOR_RESET}            Build NPU driver from source if set (default: install via DKMS)"
    echo -e ""
    echo -e "Virtual Environment Options:"
    echo -e "  ${COLOR_GREEN}[--venv_path=<PATH>]${COLOR_RESET}               Specify the path for the virtual environment"
    echo -e "                                     (Default: ${VENV_PATH_DEFAULT})"
    echo -e "Virtual Environment Sub-Options:"
    echo -e "  ${COLOR_GREEN}  [-f | --venv-force-remove]${COLOR_RESET}         (Default ON) Force remove existing virtual environment at --venv_path before creation"
    echo -e "  ${COLOR_GREEN}  [-r | --venv-reuse]${COLOR_RESET}                (Default OFF) Reuse existing virtual environment at --venv_path if it's valid, skipping creation"
    echo -e ""
    echo -e "  ${COLOR_GREEN}[-v|--verbose]${COLOR_RESET}                        Enable verbose (debug) logging"
    echo -e "  ${COLOR_GREEN}[-h|--help]${COLOR_RESET}                           Display this help message and exit"
    echo -e ""
    echo -e "${COLOR_BOLD}Examples:${COLOR_RESET}"
    echo -e "  ${COLOR_YELLOW}$0 --all${COLOR_RESET}"
    echo -e "  ${COLOR_YELLOW}$0 --all --exclude-fw${COLOR_RESET}"
    echo -e "  ${COLOR_YELLOW}$0 --target=dx_rt_npu_linux_driver${COLOR_RESET}"
    echo -e "  ${COLOR_YELLOW}$0 --target=dx_rt --venv_path=/opt/my_runtime_venv --venv-reuse${COLOR_RESET}"
    echo -e ""

    if [ "$1" == "error" ] && [[ ! -n "$2" ]]; then
        print_colored_v2 "ERROR" "Invalid or missing arguments."
        exit 1
    elif [ "$1" == "error" ] && [[ -n "$2" ]]; then
        print_colored_v2 "ERROR" "$2"
        exit 1
    elif [[ "$1" == "warn" ]] && [[ -n "$2" ]]; then
        print_colored_v2 "WARNING" "$2"
        return 0
    fi
    exit 0
}

install_dx_rt_npu_linux_driver_via_source_build() {
    sudo apt update && sudo apt-get -y install pciutils kmod build-essential make linux-headers-6.11.0-17-generic
    
    pushd "${DRIVER_PATH}"
    # if .gitmodules file is exist, submodule init and update.
    if [ -f .gitmodules ]; then
        git submodule update --init --recursive
    fi
    popd
    
    pushd "${DRIVER_PATH}/modules"
    ./build.sh
    yes n | sudo ./build.sh -c install
    sudo modprobe dx_dma
    lsmod | grep dx

    popd
}

install_dx_rt_npu_linux_driver_via_dkms() {
    local deb_pattern="${DRIVER_PATH}/release/latest/dxrt-driver-dkms*.deb"

    if compgen -G "$deb_pattern" > /dev/null; then
        pushd "${DRIVER_PATH}/release/latest" > /dev/null
        sudo apt install -y ./dxrt-driver-dkms*.deb
        popd > /dev/null
    else
        print_colored "DKMS package not found. Switching to source build installation." "WARNING"
        install_dx_rt_npu_linux_driver_via_source_build
    fi
}

uninstall_dx_rt_npu_linux_driver_via_dkms() {
    local pacakge_name="dxrt-driver-dkms"
    print_colored_v2 "INFO" "Uninstalling dkms $pacakge_name ..."

    if dpkg -l | grep -qw "$pacakge_name"; then
        print_colored_v2 "INFO" "dkms $pacakge_name package is installed. Uninstalling..."
        sudo apt purge -y "$pacakge_name" || {
            print_colored_v2 "FAIL" "Failed to uninstall dkms package. Exiting..."
            exit 1
        }
    else
        print_colored_v2 "SKIP" "dkms $pacakge_name package is not installed. Skipping..."
    fi

    print_colored_v2 "SUCCESS" "Uninstalling dkms $pacakge_name completed."
}

uninstall_dx_rt_npu_linux_driver_via_source_build() {
    print_colored_v2 "INFO" "Uninstalling dx_rt_npu_linux_driver via source build ..."

    pushd "${DRIVER_PATH}/modules"
    sudo ./build.sh -c clean || {
        print_colored_v2 "FAIL" "Failed to clean the dx_rt_npu_linux_driver. Exiting..."
        exit 1
    }
    sudo ./build.sh -c uninstall || {
        print_colored_v2 "FAIL" "Failed to uninstall the dx_rt_npu_linux_driver. Exiting..."
        exit 1
    }
    popd

    print_colored_v2 "SUCCESS" "Uninstalling dx_rt_npu_linux_driver via source build completed."
}

uninstall_dx_rt_npu_linux_driver() {
    print_colored_v2 "INFO" "Uninstalling dx_rt_npu_linux_driver..."
    
    uninstall_dx_rt_npu_linux_driver_via_dkms
    uninstall_dx_rt_npu_linux_driver_via_source_build

    print_colored_v2 "SUCCESS" "Uninstalling dx_rt_npu_linux_driver completed."
}

install_dx_rt_npu_linux_driver() {
    DX_RT_DRIVER_INCLUDED=1

    # Add driver uninstall function for prevents conflicts
    uninstall_dx_rt_npu_linux_driver

    if [ "${USE_DRIVER_SOURCE_BUILD}" = "y" ]; then
        install_dx_rt_npu_linux_driver_via_source_build
    else
        install_dx_rt_npu_linux_driver_via_dkms
    fi
}

set_use_ort() {
    pushd "${RUNTIME_PATH}/dx_rt"
    CMAKE_FILE="cmake/dxrt.cfg.cmake"

    if [ "${USE_ORT}" = "y" ]; then
        sed -i 's/option(USE_ORT *"Use ONNX Runtime" *OFF)/option(USE_ORT "Use ONNX Runtime" ON)/' "$CMAKE_FILE"
        print_colored "USE_ORT option has been set to ON in dx_rt/$CMAKE_FILE" "INFO"
    else
        sed -i 's/option(USE_ORT *"Use ONNX Runtime" *ON)/option(USE_ORT "Use ONNX Runtime" OFF)/' "$CMAKE_FILE"
        print_colored "USE_ORT option is set to '${USE_ORT}'. so, USE_ORT option has been set to OFF in dx_rt/$CMAKE_FILE" "INFO"
    fi 

    popd
}

# sanity_check() {
#     echo "--- sanity check... ---"

#     if [ "${USE_SANITY_CHECK}" = "y" ]; then
#         ${RUNTIME_PATH}/scripts/sanity_check.sh
#         if [ $? -ne 0 ]; then
#             print_colored "Sanity Check failed. Exiting." "ERROR"
#             exit 1
#         fi
#     else
#         print_colored "Skipped to Sanity Check..." "WARNING"
#     fi
# }

install_dx_rt() {
    DX_RT_INCLUDED=1
    set_use_ort

    . "${VENV_PATH}/bin/activate" || { print_colored_v2 "ERROR" "venv(${VENV_PATH}) activation failed. Exiting."; exit 1; }

    pushd "$SCRIPT_DIR/dx_rt"
    if [ "${USE_ORT}" = "y" ]; then
        ./install.sh --all
    else
        ./install.sh --dep
    fi || { print_colored_v2 "ERROR" "dx_rt install failed. Exiting."; exit 1; }
    
    ./build.sh --clean || { print_colored_v2 "ERROR" "dx_rt install failed. Exiting."; exit 1; }
    popd
}

install_dx_rt_python_api() {
    print_colored_v2 "INFO" "=== Setup 'dx_engine' Python API... ==="

    . "${VENV_PATH}/bin/activate" && \
    pushd "${RT_PATH}/python_package" && \
    pip install . && \
    popd
    if [ $? -ne 0 ]; then
        print_colored_v2 "ERROR" "'dx_engine' Python API setup failed. Exiting."
        exit 1
    fi
    print_colored_v2 "INFO" "[OK] Setup 'dx_engine' Python API"
}

install_dx_app() {
    DX_APP_INCLUDED=1

    pushd "$SCRIPT_DIR/dx_app"
    ./install.sh --all
    ./build.sh --clean
    popd
}

install_dx_stream() {
    pushd "$SCRIPT_DIR/dx_stream"
    ./install.sh
    ./build.sh --install
    # gst-inspect-1.0 dxstream
    popd
}

install_dx_fw() {
    if [ "${EXCLUDE_FW}" = "y" ]; then
        print_colored_v2 "WARNING" "Excluding firmware update."
        return
    fi

    if [ ! -f "$SCRIPT_DIR/dx_fw/m1/latest/mdot2/fw.bin" ]; then
        print_colored_v2 "ERROR" "firmware file not found!"
        exit 1
    fi

    if ! command -v dxrt-cli &> /dev/null; then
        print_colored_v2 "ERROR" "'dxrt-cli' not found!"
        exit 1
    fi

    dxrt-cli -g "$SCRIPT_DIR/dx_fw/m1/latest/mdot2/fw.bin"
    dxrt-cli -u "$SCRIPT_DIR/dx_fw/m1/latest/mdot2/fw.bin"
    print_colored_v2 "HINT" "It is recommended to power off completely and reboot after the firmware update."
}

install_python() {
    print_colored "--- install python... ---" "INFO"

    local INSTALL_PY_CMD_ARGS=""

    if [ -n "$VENV_PATH" ]; then
        INSTALL_PY_CMD_ARGS+=" --venv_path=$VENV_PATH"
    fi
    
    if [ "${VENV_FORCE_REMOVE}" = "y" ]; then
        INSTALL_PY_CMD_ARGS+=" --venv-force-remove"
    fi

    if [ "${VENV_REUSE}" = "y" ]; then
        INSTALL_PY_CMD_ARGS+=" --venv-reuse"
    fi

    # Pass the determined VENV_PATH and new options to install_python_and_venv.sh
    INSTALL_PY_CMD="${RUNTIME_PATH}/scripts/install_python_and_venv.sh ${INSTALL_PY_CMD_ARGS}"
    echo "CMD: ${INSTALL_PY_CMD}"
    ${INSTALL_PY_CMD}
    if [ $? -ne 0 ]; then
        print_colored "Python and Virtual environment setup failed. Exiting." "ERROR"
        exit 1
    fi

    print_colored "[OK] Completed to install python" "INFO"
}

host_reboot() {
    print_colored "The 'dx_rt_npu_linux_driver' has been installed." "INFO"
    print_colored "To complete the installation, the system must be restarted."
    echo -e -n "${COLOR_BRIGHT_GREEN_ON_BLACK}  Would you like to reboot now? (y/n): ${COLOR_RESET}"
    read -r answer
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        echo "Start reboot..."
        sudo reboot now
    fi
}

show_information_message() {
    if [[ ${DX_RT_INCLUDED} -eq 1 || ${DX_APP_INCLUDED} -eq 1 ]]; then
        print_colored "To activate the virtual environment, run:" "HINT"
        print_colored "  source ${VENV_PATH}/bin/activate " "HINT"
    fi

    if [ ${DX_RT_DRIVER_INCLUDED} -eq 1 ]; then
        host_reboot
    fi
}

main() {
    # this function is defined in scripts/common_util.sh
    # Usage: os_check "supported_os_names" "ubuntu_versions" "debian_versions"
    os_check "ubuntu debian" "18.04 20.04 22.04 24.04" "12"

    # this function is defined in scripts/common_util.sh
    # Usage: arch_check "supported_arch_names"
    arch_check "amd64 x86_64 arm64 aarch64 armv7l"

    case $TARGET_PKG in
        dx_rt_npu_linux_driver)
            print_colored "Installing dx_rt_npu_linux_driver..." "INFO"
            install_dx_rt_npu_linux_driver
            show_information_message
            print_colored "[OK] Installing dx_rt_npu_linux_driver" "INFO"
            ;;
        dx_rt)
            print_colored "Installing dx_rt..." "INFO"
            install_python
            install_dx_rt
            install_dx_rt_python_api
            show_information_message
            print_colored "[OK] Installing dx_rt" "INFO"
            ;;
        dx_app)
            print_colored "Installing dx_app..." "INFO"
            install_python
            install_dx_rt
            install_dx_rt_python_api
            install_dx_app
            show_information_message
            print_colored "[OK] Installing dx_app" "INFO"
            ;;
        dx_stream)
            print_colored "Installing dx_stream..." "INFO"
            install_dx_stream
            show_information_message
            print_colored "[OK] Installing dx_stream" "INFO"
            ;;
        dx_fw)
            print_colored "Installing dx_fw..." "INFO"
            install_dx_fw
            show_information_message
            print_colored "[OK] Installing dx_fw" "INFO"
            ;;
        all)
            print_colored "Installing all runtime modules..." "INFO"
            install_python
            install_dx_rt
            install_dx_rt_python_api
            install_dx_fw
            install_dx_app
            install_dx_stream
            install_dx_rt_npu_linux_driver
            # sanity_check              # disabled for now, cause: driver is detected after reboot and it's not installed yet.
            show_information_message
            print_colored "[OK] Installing all runtime modules" "INFO"
            ;;
        *)
            show_help "error" "The '--all' option was not specified, or the '--target' option is invalid. Target packages will not be installed."
            ;;
    esac
}

DX_RT_INCLUDED=0
DX_APP_INCLUDED=0
DX_RT_DRIVER_INCLUDED=0

TARGET_PKG=""
EXCLUDE_FW="n"
USE_ORT="y"
# USE_SANITY_CHECK="y"
USE_COMPILED_VERSION_CHECK="y" # This variable is not used in the provided script, kept for consistency.

# variables for venv options
USE_DRIVER_SOURCE_BUILD="n"
VENV_PATH_ARG="" # Stores user-provided venv path
VENV_FORCE_REMOVE="y"
VENV_REUSE="n"

# parse args
for i in "$@"; do
    case "$1" in
        --all)
            TARGET_PKG=all
            ;;
        --exclude-fw)
            EXCLUDE_FW="y"
            ;;
        --exclude-fw)
            EXCLUDE_FW="y"
            shift # past argument
            ;;
        --target=*)
            TARGET_PKG="${1#*=}"
            ;;
        --use-ort=*)
            USE_ORT="${1#*=}"
            ;;
        # --sanity-check=*)
        #     USE_SANITY_CHECK="${1#*=}"
        #     ;;
        --driver-source-build)
            USE_DRIVER_SOURCE_BUILD="y"
            ;;
        --venv_path=*)
            VENV_PATH="${1#*=}"
            ;;
        -f|--venv-force-remove)
            VENV_FORCE_REMOVE="y"
            ;;
        -r|--venv-reuse)
            VENV_REUSE="y"
            ;;
        -v|--verbose)
            ENABLE_DEBUG_LOGS=1
            ;;
        -h|--help)
            show_help
            ;;
        *)
            show_help "error" "Invalid option '$1'"
            ;;
    esac
    shift
done

main

exit 0
