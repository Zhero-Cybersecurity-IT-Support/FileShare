<#
    Author: Louis Oosthuizen - Zhero Cybersecurity

    Script which reinstalls N-central for windows machines. This script requires certain variables to work including, URL, CLIENTID, APIURL & JWT
#>
# First determine if N-central is on the asset or not
$NCentralStatus = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Windows Agent*" }
$NCentralCode=$NCentralStatus.IdentifyingNumber
if($NCentralCode){
    Write-Host "N-central found is installed, removing now..."
    Start-Process "msiexec.exe" -ArgumentList "/x $NCentralCode /qn" -Wait
    Write-Host "[SUCCESS] Removal complete."
}

# Now install N-central again but to your server
if (-not (Test-Path -Path "C:\AutomateResources")) {
    New-Item -ItemType Directory -Path "C:\AutomateResources" | Out-Null
}
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri "https://ncod659.n-able.com/download/2024.4.0.11/winnt/N-central/WindowsAgentSetup.exe" -OutFile "C:\AutomateResources\WindowsAgentSetup.exe" -ErrorAction SilentlyContinue
}
catch {
    Write-Host "An error has occured: $_"
}

# Before installing, get some vital information about the client
#soap request
try{
    Write-Host "Retrieving registration token now..."
$Envelope = @"
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
    <Body>
        <customerList xmlns="http://ei2.nobj.nable.com/">
            <password>$JWT</password>
            <settings>
                <key>listSOs</key>
                <value>false</value>
            </settings>
        </customerList>
    </Body>
</Envelope>
"@
    $RESPONSE = (Invoke-RestMethod -Uri $APIURL -Method Post -ContentType "application/soap+xml; charset=utf-8" -Headers @{"SOAPAction"="POST"} -Body $Envelope).OuterXml
    # Parse data and split by customer
    $ALLCUSTOMERS = $RESPONSE -replace "</return><return>", "</return>`n`n<return>"
    # Now find the array item which equals the customer id
    $CUSTOMER = $ALLCUSTOMERS -split "</return>\s*<return>" | Where-Object { $_ -match "customerid</key><value>$CUSTOMERID<" }
    $REGISTRATION_TOKEN = (($CUSTOMER -replace "</second><key>customer.registrationtoken", '£' -replace 'customer.registrationtoken</first><second xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="xs:string">',"£")  -split '£')[1]
    Write-Host "[SUCCESS] Registration token retrieved."
}catch{
    Write-Host "[ERROR] An error occurred while retrieving the registration token: $_"
}
# Run installation with acquired client data
try{
    Write-Host "Installing N-central now..."
    $arguments = @(
    '/s',
    '/v"',
    '/qn',
    "CUSTOMERID=$CUSTOMERID",
    'CUSTOMERSPECIFIC=1',
    "REGISTRATION_TOKEN=$REGISTRATION_TOKEN",
    'SERVERPROTOCOL=HTTPS',
    "SERVERADDRESS=$URL",
    'SERVERPORT=443"'
    )
    Start-Process 'C:\AutomateResources\WindowsAgentSetup.exe'  -ArgumentList $arguments -Wait -WindowStyle Hidden
    Write-Host "[SUCCESS] N-central Installation complete."
}
catch {
    Write-Host "[ERROR] An error occurred while installing N-able Windows Agent: $_"
}
