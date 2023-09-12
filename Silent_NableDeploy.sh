#!/bin/sh
# Installs the N-central Mac agent without requiring user interaction. Suitable for 
# distribution via an existing RMM or other remote control solution. Intended to be
# run as root or via sudo
# 
# Thanks to the following partners for their assistance developing and testing:
# 
#  Adam Gossett, Henry Bonath, Jason Hanschu - https://www.thinkcsc.com/
#  Adapted for use by Louis Oosthuizen - https://www.zhero.co.uk/ - Applicable for 2023.5
# 
echo "Checking for superuser..."
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run with sudo"
	exit 1
else
	echo "OK"	
fi
inputErrorMsg="usage:-u SERVERURL -p JWT -r CUSTOMERID"
while getopts "u: p: r:" option; do
case "${option}" in
	u)
		SERVERURL=${OPTARG} ;;
	p)
		JWT=${OPTARG} ;;
	r)
		CUSTOMERID=${OPTARG} ;;
        esac
done

# clean up server address if necessary
SERVERURL=$( echo "${SERVERURL}" | awk -F "://" '{if($2) print $2; else print $1;}' )
SERVERURL=${SERVERURL%/} 	# strip trailing slash

echo "SERVER URL: $SERVERURL"


# generate URL for API access
APIURL="$SERVERURL/dms2/services2/ServerEI2"
echo "API URL $APIURL"

# build the URL for the DMG and install script
NCVERSION=$(curl -s --header 'Content-Type: application/soap+xml; charset="utf-8"' --header 'SOAPAction:POST' \
--data '<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope"><Body><versionInfoGet xmlns="http://ei2.nobj.nable.com/"><credentials><password>'$JWT\
'</password></credentials></versionInfoGet></Body></Envelope>' $APIURL | sed 's,</value>,\n,g' | grep -m1 -i Product\ Version | awk -F'</key><value>' '{print $2}')

echo "N-CENTRAL VERSION: $NCVERSION"

SCRIPTURL="https://$SERVERURL/download/1.6.0.0/macosx/N-central/silent_install.sh"

echo "SCRIPT URL: $SCRIPTURL"

DMGURL="https:/$SERVERURL/download/1.8.0.460/macosx/N-central/Install_N-central_Agent_v1.8.0.460.dmg"

echo "DMG URL: $DMGURL"

# fetch the registration token and customer name for the specified customer ID
RESPONSE=$(curl -s --header 'Content-Type: application/soap+xml; charset="utf-8"' --header 'SOAPAction:POST' --data '<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope"><Body><customerList xmlns="http://ei2.nobj.nable.com/"><password>'$JWT'</password><settings><key>listSOs</key><value>false</value></settings></customerList></Body></Envelope>' \
$APIURL | sed s/\<return\>/\\n\<return\>/g | grep customerid\</key\>\<value\>$CUSTOMERID\< )

if [ $? -gt 0 ] || [ -z "$RESPONSE" ]
then
	echo "ERROR FETCHING REGISTRATION TOKEN FROM $APIURL \n CONFIRM JWT AND CUSTOMER ID."
	echo "RESPONSE: $RESPONSE"
	exit 1
fi

CUSTOMERNAME=$(echo $RESPONSE | sed s/\>customer/\\n/g | grep -m1 customername | cut -d \> -f 3 | cut -d \< -f 1)

echo "CUSTOMER NAME: $CUSTOMERNAME"

TOKEN=$(echo $RESPONSE | sed s/customer./\\n/g | grep -m1 registrationtoken | cut -d \> -f 3 | cut -d \< -f 1)


echo "REGISTRATION TOKEN: $TOKEN"

if [ ! -d "/tmp/NCENTRAL/" ] ;
then
	echo "Creating temp download directory."
	mkdir "/tmp/NCENTRAL/"
fi
	

# get the installer pieces
if [ ! -f "/tmp/NCENTRAL/MacAgentInstallation.dmg" ];
then 
	echo "Downloading DMG"
	curl -o "/tmp/NCENTRAL/MacAgentInstallation.dmg" -s $DMGURL
	if [ $? -gt 0 ]
	then
		echo "ERROR DOWNLOADING $DMGURL"
		exit 1
	fi
fi

if [ ! -f  "/tmp/NCENTRAL/dmg-install.sh" ];
then
	echo "Downloading install script"
	curl -o "/tmp/NCENTRAL/dmg-install.sh" -s $SCRIPTURL
	if [ $? -gt 0 ]
	then
		echo "ERROR DOWNLOADING $SCRIPTURL"
		exit 1
	fi
fi

# expand the installer script
# echo "Decompressing install script"
# tar -C /tmp/NCENTRAL/ -xz -f /tmp/NCENTRAL/dmg-install.sh.tar.gz

# run the installer script
cd /tmp/NCENTRAL/ || return

/bin/bash dmg-install.sh -s "$SERVERURL" -c "$CUSTOMERNAME" -i "$CUSTOMERID" -t "$TOKEN" -I "/tmp/NCENTRAL/MacAgentInstallation.dmg"

sleep 5
echo "Cleaning Up Files"
sudo rm -rf "/tmp/NCENTRAL/"