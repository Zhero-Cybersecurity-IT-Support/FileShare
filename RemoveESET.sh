#!/bin/bash

function ESET_Removal() {
    sudo /Applications/ESET\ Endpoint\ Antivirus.app/Contents/Helpers/Uninstaller.app/Contents/Scripts/uninstall.sh
    # Remove EndPoint
    sudo killall -9 "ESET Endpoint Antivirus"
    sudo rm -rf "/applications/ESET Endpoint Antivirus.app"
    sudo rm -rf "/Library/LaunchAgents/com.eset.esets_gui.plist"
    # Remove daemon
    sudo launchctl unload /Library/LaunchDaemons/com.eset.esets_daemon.plist
    sudo rm -rf "/Library/LaunchDaemons/com.eset.esets_daemon.plist"

    # Remove Manager
    sudo zsh /Applications/ESET\ Management\ Agent.app/Contents/Scripts/Uninstall.command

    # Remove left over files
    sudo rm -Rf "/Library/Application Support/ESET"
}

ESET_Removal