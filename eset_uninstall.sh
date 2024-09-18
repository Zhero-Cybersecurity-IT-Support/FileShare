#!/bin/bash

# Get bundle path
readonly SCRIPTS_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
readonly UNINSTALLER_BUNDLE_PATH="$( dirname "$(dirname "$SCRIPTS_PATH")" )"
readonly PRODUCT_APPLICATION_SUPPORT_PATH="$(dirname "$UNINSTALLER_BUNDLE_PATH")"
readonly PRODUCT_NAME="$( basename "$PRODUCT_APPLICATION_SUPPORT_PATH" | cut -f 1 -d '.' )"
readonly HELPER_PATH="${UNINSTALLER_BUNDLE_PATH}/Contents/Helpers"

# Help
readonly HELP="Help: This script will uninstall $PRODUCT_NAME. Uninstallation could be made only by user with root privileges"

readonly tasks=(
	#name                    path                                                                     param         uninstall    upgrade
	"ut1"                    "${HELPER_PATH}/ut1"                                                     ""            true         true
	"ut-dissociate"          "${HELPER_PATH}/ut-dissociate"                                           ""            true         false
	"sext-uninstaller"       "${HELPER_PATH}/sext_uninstaller.app/Contents/MacOS/sext_uninstaller"    "$1 $2 $3"    true         true
	"ut2"                    "${HELPER_PATH}/ut2"                                                     ""            true         true
	"ut3"                    "${HELPER_PATH}/ut3"                                                     ""            true         true
	"ut4"                    "${HELPER_PATH}/ut4"                                                     ""            true         true
	"ut5"                    "${HELPER_PATH}/ut5"                                                     ""            true         true
	"ut6"                    "${HELPER_PATH}/ut6"                                                     "$1"          true         true
	"ut-privacy-settings"    "${HELPER_PATH}/ut-privacy_settings"                                     ""            true         false
	"ut7"                    "${HELPER_PATH}/ut7"                                                     "$1"          true         true
)

readonly name_idx=0
readonly path_idx=1
readonly param_idx=2
readonly uninstall_idx=3
readonly upgrade_idx=4
readonly columns=5
readonly size=${#tasks[@]}
execute_idx=${uninstall_idx}

# Handle params
while getopts 'hu-:' option; do
	case "$option" in
		-)
			case "${OPTARG}" in
				help)
					echo "$HELP"
					exit
					;;
				upgrade)
					execute_idx=${upgrade_idx}
					;;
				*)	echo "Error: Invalid option --${OPTARG}\n" >&2
					echo "$HELP" >&2
					exit 1
					;;
			esac
			;;
		"h")
			echo "$HELP"
			exit
			;;
		"u")
			execute_idx=${upgrade_idx}
			;;
		*)
			echo "Error: Invalid option: ${OPTARG}" >&2
			echo "$HELP" >&2
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))

if [ $EUID -ne 0 ]; then
	echo "Error: Uninstallation could be made only by user with root privileges" >&2
	exit 2
fi

# Logs
readonly LOG_PATH="$PRODUCT_APPLICATION_SUPPORT_PATH/uninstallation_log"
rm -f "$LOG_PATH"

function log_message() {
	MESSAGE="$1"
	echo "uninstall.sh: $MESSAGE" >> "$LOG_PATH"
	echo "$MESSAGE" >&2
}

# Main
log_message "Starting uninstallation procedure"
if [ -d "$UNINSTALLER_BUNDLE_PATH" ]
then
	for (( i=0; i<${size}; i+=${columns} ))
	do
		task_name=${tasks[$((${i} + ${name_idx}))]}
		task_path=${tasks[$((${i} + ${path_idx}))]}
		task_param=${tasks[$((${i} + ${param_idx}))]}
		task_run=${tasks[$((${i} + ${execute_idx}))]}

		if [[ ${task_run} == true ]]
		then
			if [ -z "${task_param}" ]
			then
				log_message "Executing uninstaller tool ${task_name}..."
			else
				log_message "Executing uninstaller tool ${task_name} ${task_param}"
			fi
			"${task_path}" ${task_param} >> "${LOG_PATH}" 2>&1
			EXIT_VALUE=$?
			if [ "$EXIT_VALUE" -ne 0 ]
			then
				log_message "Error: uninstallation step ${task_name} failed with error ${EXIT_VALUE}! Cannot execute correxctly tool: '${task_path}' ${task_param}"
			fi
		else
			log_message "Skipping uninstaller tool ${task_name}"
		fi		
	done
	log_message "Uninstallation finished successfully!"
	exit 0
else
	log_message "Error: Uninstallation failed. Unable to find bundle."
	exit 3
fi
