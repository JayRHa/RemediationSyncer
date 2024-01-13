<#
Version: 2.0
Author: Jannik Reinhard (jannikreinhard.com)
Script: Remediation_syncer
Description:
Sync scripts from an repository with intune
Release notes:
Version 1.0: Init
#> 

#TODO:
# - Compare Yaml with Intune
# - Add support for multiple groups
# - Add support for multiple schedules
# - Write Logfile

# Check if Microsoft Graph module is installed
function Install-Module {
    param(
        [string]$Name,
        [string]$Scope
    )
    $module = Get-Module -Name $Name -ListAvailable
    if ($module -eq $null) {
        Install-Module -Name $Name -Scope $Scope -Force
        Import-Module $Name -Global
    } else {
        Write-Host "Microsoft $Name is already installed."
    }
}

Install-Module -Name Microsoft.Graph -Scope CurrentUser
Install-Module -Name Microsoft.Graph.Intune -Scope CurrentUser
Install-Module -Name powershell-yaml -Scope CurrentUser

# Authentication
Connect-MgGraph -tenantid f849cde7-f11d-4ef5-a31d-7fca98b21bf5

###############################################################################################################
# Functions ###################################################################################################
###############################################################################################################
function Get-IntuneRemediationScripts {
    $graphApiVersion = "Beta"
    $graphUrl = "https://graph.microsoft.com/$graphApiVersion"
    $remediationScripts = Invoke-MGGraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts" -Method GET
    return ($remediationScripts.value | ConvertTo-Json -Depth 100) | ConvertFrom-Json
}

function Invoke-HealthscriptUpload {
    param(
        [string]$DisplayName,
        [string]$Description,
        [string]$Publisher,
        [string]$RunAs,
        [string]$RunAs32,
        [string]$ScheduleType,
        [string]$ScheduleFrequency,
        [string]$StartTime,
        [string]$Groupid,
        [string]$DetectionScriptContent,
        [string]$RemediationScriptContent,
        [string]$EnforceSignatureCheck
    )

    $url = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts"
    $detectionbase64encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($DetectionScriptContent))
    $remediationbase64encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($RemediationScriptContent))

    $json = @"
    {
        "description": "$Description",
        "detectionScriptContent": "$detectionbase64encoded",
        "displayName": "$DisplayName",
        "enforceSignatureCheck": $EnforceSignatureCheck,
        "publisher": "$Publisher",
        "remediationScriptContent": "$remediationbase64encoded",
        "roleScopeTagIds": [
            "0"
        ],
        "runAs32Bit": $RunAs32,
        "runAsAccount": "$RunAs"
    }
"@
    $addscript = Invoke-MgGraphRequest -Uri $url -Method Post -Body $json -ContentType "application/json" -OutputType PSObject
    $scriptid = $addscript.id

    if($ScheduleType -eq "Daily"){
        $Schedule = @"
        "runSchedule": {
            "@odata.type": "#microsoft.graph.deviceHealthScriptDailySchedule",
            "interval": $scheduleFrequency,
            "time": "$startTime",
            "useUtc": false
        },
"@
    }else{
        $Schedule = @"
        "runSchedule": {
            "@odata.type": "#microsoft.graph.deviceHealthScriptHourlySchedule",
            "interval": $interval
        },
"@
    }
    $assignurl = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$scriptid/assign"
    $assignjson = @"
    {
        "deviceHealthScriptAssignments": [
            {
                "runRemediationScript": true,
                $schedule
                "target": {
                    "@odata.type": "#microsoft.graph.groupAssignmentTarget",
                    "groupId": "$groupid"
                }
            }
        ]
    }
"@
    Invoke-MgGraphRequest -Uri $assignurl -Method Post -Body $assignjson -ContentType "application/json" -OutputType PSObject

}

###############################################################################################################
# Main ########################################################################################################
###############################################################################################################

# Call the function
$scripts = Get-IntuneRemediationScripts

# Get all scripts in folder
$folders = Get-ChildItem -Path .\remediation-scripts -Directory
Write-Host $folders.Name

# Check for each folder name if there is an $script.displayName available
foreach ($folder in $folders) {
    $script = $scripts | Where-Object { $_.displayName -eq $folder.Name }
    if ($script -eq $null) {
        Write-Host "Script not found in Intune: $folder.Name"
        #Read Yaml
        $yaml = Get-Content -Path "$folder\definition.yaml" -Raw | ConvertFrom-Yaml
        Write-Host $yaml
        #Upload Script
        #Invoke-HealthscriptUpload -DisplayName $yaml.displayName -Description $yaml.description -Publisher $yaml.publisher -RunAs $yaml.runAs -RunAs32 $yaml.runAs32 -ScheduleType $yaml.scheduleType -ScheduleFrequency $yaml.scheduleFrequency -StartTime $yaml.startTime -Groupid $yaml.groupid -DetectionScriptContent (Get-Content -Path ".\remediation-scripts\$folder\detection.ps1" -Raw) -RemediationScriptContent (Get-Content -Path ".\remediation-scripts\$folder\remediation.ps1" -Raw) -EnforceSignatureCheck $yaml.enforceSignatureCheck
    }else{
        Write-Host "Script found in Intune: $folder.Name"
        #Compare Yaml with Intune
        $yaml = Get-Content -Path "$folder\definition.yaml" -Raw | ConvertFrom-Yaml
        #......
    }
}