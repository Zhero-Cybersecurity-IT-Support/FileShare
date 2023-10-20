#!/bin/sh

################################################################################
# Uninstalls the Agent and all artifacts.
#
# The script requires elevated privileges (`sudo`). The following actions are 
# performed:
#   - Stops services: 
#       - `com.n-central.agent.plist`
#       - `com.n-central.agent.logrotate-daily.plist`
#   - Removes all components installed by the Agent:
#       - MSP Anywhere Helper
#       - MDMHelper
#   - Removes:
#       - All files associated with the `com.n-central.pkg.agent` package
#       - Obsolete agent directories
#       - Symlinks
#       - Agent install directory
#       - Agent log directory
#
# Usage:
#   `sudo uninstall.tool`
#
################################################################################

set_constants()
{
    readonly LOG_DIR="/Library/Logs/N-central Agent"
    readonly INSTALL_DIR="/Library/N-central Agent"

    readonly PACKAGE_MASK="com.n-central.pkg.agent"

    readonly LAUNCH_DAEMON_PATH="/Library/LaunchDaemons/com.n-central.agent.plist"
    readonly LOG_ROTATE_JOB_PATH="/Library/LaunchDaemons/com.n-central.agent.logrotate-daily.plist"

    readonly MDM_HELPER_UNINSTALL_TOOL="/Library/DeviceManagementHelper/uninstall.tool"
    readonly MSPA_HELPER="/Applications/MSP Anywhere Agent N-Central.app/Contents/Resources/MSP Anywhere Helper"

    readonly EDR_DIRECTORY="/Library/N-central Agent/modules/EDR"
    readonly EDR_MODULE="/Library/N-central Agent/modules/EDR/msp-lwt-edr-module"
    readonly EDR_UNINSTALL_CONFIG="/Library/N-central Agent/modules/EDR/msp_lwt_edr_uninstall.json"

    readonly LEGACY_NAGENT_DIR="/Applications/N-agent"

    readonly LOG_FILENAME="nagent.uninstall.log"
    readonly LOG_FILEPATH="${LOG_DIR}/${LOG_FILENAME}"

    readonly EXIT_SUCCESS=0
    readonly EXIT_FAILED=1
    readonly EXIT_ERROR_INVALID_PARAMETERS=3
    readonly EXIT_ERROR_NO_SUDO=4
}

################################################################################
# Functions
################################################################################

check_if_running_as_sudo() 
{
    if [ "$(id -u)" -ne 0 ]; then
        echo "Please run as root:"
        echo "    $0"

        exit ${EXIT_ERROR_NO_SUDO}
    fi
}

################################################################################

log_info() # message
{
    log_message "$1" false
}

log_warning() # message
{
    log_message "$1" true
}

log_message() # message, is_warning
(
    if [ -d "${LOG_DIR}" ]; then
        prefix="I"

        if ${2}; then
            prefix="W"
        fi

        CURRENT_TIME=$(date '+%Y-%m-%d %T')
        readonly CURRENT_TIME

        echo "[${CURRENT_TIME}] [${prefix}] $1" >> "${LOG_FILEPATH}"
    fi
)

################################################################################

remove_file_or_folder() # pathname
(
    # Parameters
    readonly PATHNAME="$1"

    log_info "Removing '${PATHNAME}':"

    if ! [ -d "${PATHNAME}" ] && ! [ -f "${PATHNAME}" ]; then
        log_warning "  Skipped '${PATHNAME}', does not exists"

        return
    fi

    if ! ERROR_MESSAGE=$(rm -rf "${PATHNAME}" 2>&1); then 
        log_warning "  Failed to remove '${PATHNAME}', error: ${ERROR_MESSAGE}"
    fi
)

remove_package_by_mask() # mask
(
    # Parameters
    readonly MASK="$1"

    if [ -z "${MASK}" ]; then
        echo "remove_package_by_mask: MASK can't be empty"

        exit ${EXIT_ERROR_INVALID_PARAMETERS}
    fi
    
    # Find the package by mask
    PACKAGE_NAME="$(pkgutil --pkgs | grep "${MASK}" | sed -n 1p)"

    if [ -z "${PACKAGE_NAME}" ]; then
        return ${EXIT_FAILED}
    fi
    
    log_info "Remove package: '${PACKAGE_NAME}'"

    
    # Find and remove all files and folders associated with the package
    
    pkgutil --only-files --files "${PACKAGE_NAME}" | while read -r file; do
        remove_file_or_folder "/${file}"
    done

    pkgutil --only-dirs --files "${PACKAGE_NAME}" | while read -r dir; do
        if [ "${dir##*.}" = "app" ]; then
            remove_file_or_folder "/${dir}"  
        fi
    done

    if ! ERROR_MESSAGE=$(pkgutil --forget "${PACKAGE_NAME}" 2>&1); then 
        log_warning "Failed to uninstall, error: ${ERROR_MESSAGE}"
    else
        log_info "Package ${PACKAGE_NAME} was successfully uninstalled"
    fi

    return ${EXIT_SUCCESS}
)

uninstall_component() # component_name, uninstall_tool, arguments
(
    # Parameters
    readonly COMPONENT_NAME="$1"
    readonly UNINSTALL_TOOL="$2"
    readonly ARGUMENTS="$3"

    if [ -z "${COMPONENT_NAME}" ] || [ -z "${UNINSTALL_TOOL}" ]; then
        echo "uninstall_component: Arguments can't be empty"

        exit ${EXIT_ERROR_INVALID_PARAMETERS}
    fi

    # Run uninstall tool if it exists 

    log_info "Uninstall component: '${COMPONENT_NAME}'"

    if [ ! -f "${UNINSTALL_TOOL}" ]; then
        log_warning "The unistallation tool ${UNINSTALL_TOOL} doesn't exist"

        return
    fi

    if ! ERROR_MESSAGE=$("${UNINSTALL_TOOL}" "${ARGUMENTS}" 2>&1); then 
        log_warning "Failed to uninstall, error: ${ERROR_MESSAGE}"
    else 
        log_info "Component '${COMPONENT_NAME}' was successfully uninstalled"
    fi
)

uninstall_module() # module_name, module_location, arguments
(
    # Parameters
    readonly MODULE_NAME="$1"
    readonly MODULE_LOCATION="$2"
    shift 2

    # Confirm that the module exists
    if ! [ -d "${MODULE_LOCATION}" ] && ! [ -f "${MODULE_LOCATION}" ]; then
        log_warning "Skipped '${MODULE_NAME}', does not exists in '${MODULE_LOCATION}'"

        return
    fi

    log_info "Uninstalling ${MODULE_NAME}..."

    # Execute command
    OUTPUT=$("${MODULE_LOCATION}" "$@" 2>&1)
    EXIT_STATUS=$?

    if [ ${EXIT_STATUS} -ne 0 ]; then
        log_warning "Uninstallation of '${MODULE_NAME}' failed with exit status: ${EXIT_STATUS}"
        log_info "Output: ${OUTPUT}"
    else
        log_info "Uninstallation of '${MODULE_NAME}' successful."
    fi
)

unload_daemon() # plist_filepath
(
    # Parameters
    readonly PLIST_FILEPATH="$1"

    if [ -z "${PLIST_FILEPATH}" ]; then
        echo "unload_daemon: Arguments can't be empty"

        exit ${EXIT_ERROR_INVALID_PARAMETERS}
    fi

    # Unload service

    log_info "Unload service: '${PLIST_FILEPATH}'"

    ERROR_MESSAGE=$(launchctl unload "${PLIST_FILEPATH}" 2>&1)

    # `launchctl unload` always returns success, even if the service doesn't exist
    # so here we are checking if `ERROR_MESSAGE` is not empty, it means unloading failed
    
    if [ -n "${ERROR_MESSAGE}" ]; then 
        log_warning "Failed to unload, error: ${ERROR_MESSAGE}"
    else 
        log_info "Daemon '${PLIST_FILEPATH}' was successfully unloaded"
    fi
)

################################################################################
# Main entry point
################################################################################

main()
{
    set_constants
    check_if_running_as_sudo

    log_info "-----------------------------"
    log_info "- Uninstallation started!   -"
    log_info "-----------------------------"

    # Stop services
    unload_daemon "${LAUNCH_DAEMON_PATH}"
    unload_daemon "${LOG_ROTATE_JOB_PATH}"

    # Uninstall third-party software, installed by the agent
    uninstall_module "EDR" "${EDR_MODULE}" uninstall --configpath="${EDR_UNINSTALL_CONFIG}"

    uninstall_component "MDMHelper" "${MDM_HELPER_UNINSTALL_TOOL}"
    uninstall_component "MSPA" "${MSPA_HELPER}" "-uninstall"

    # Clean up package contents
    if ! remove_package_by_mask "${PACKAGE_MASK}"; then
        log_warning "Package was not found by mask ${PACKAGE_MASK}. Fallback to manual uninstall"
        remove_file_or_folder "${LAUNCH_DAEMON_PATH}"
        remove_file_or_folder "${LOG_ROTATE_JOB_PATH}"
    fi

    # Agent directories
    remove_file_or_folder "${LEGACY_NAGENT_DIR}"
    remove_file_or_folder "${INSTALL_DIR}"
    remove_file_or_folder "${EDR_DIRECTORY}"

    log_info "-----------------------------"
    log_info "- Uninstallation completed! -"
    log_info "-----------------------------"

    remove_file_or_folder "${LOG_DIR}"

    # Unload and Kill App
    sudo launchctl unload /Library/LaunchDaemons/com.mspanywhere.agent.daemon-N-central.plist
    sudo killall -9 "MSP Anywhere Agent N-central"
    # Remove Folders for App
    sudo rm -rf "/applications/Take Control Viewer for N-central.app" "/applications/MSP Anywhere Agent N-central.app" "/Library/MSP Anywhere Agent N-central" "/Library/LaunchDaemons/com.mspanywhere.agent.daemon-N-central.plist" "/Library/LaunchDaemons/com.mspanywhere.agent.helper-N-central.plist" "/Library/LaunchAgents/MSPAViewerN-centralLoader.plist" "/Library/LaunchAgents/com.mspanywhere.agent.agent-N-central.plist" "/Library/LaunchAgents/com.mspanywhere.agent.agentPL-N-central.plist" "/Library/LaunchAgents/com.mspanywhere.agent.configurator-N-central.plist" "/Library/Logs/MSP Anywhere Agent N-central"


    exit ${EXIT_SUCCESS}
}

################################################################################

main "$@"