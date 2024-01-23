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
$graphApiVersion = "Beta"
$graphUrl = "https://graph.microsoft.com/$graphApiVersion"

function Get-IntuneRemediationScripts {
    $remediationScripts = Invoke-MGGraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts" -Method GET

    # Get also assignments and schedules
    foreach ($remediationScript in $remediationScripts.value) {
        $assignments = Invoke-MGGraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts/$($remediationScript.id)/assignments" -Method GET
        $propertiesToRemoveFromAssignments = 'id', '@odata.context', "target.'@odata.type'"
        $remediationScript.assignments = $assignments.value | Select-Object -Property * -ExcludeProperty $propertiesToRemoveFromAssignments
    # $remediationScript.schedules = Invoke-MGGraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts/$($remediationScript.id)/schedules" -Method GET
    }

    # Exclude specified properties
    $propertiesToRemove = 'detectionScriptParameters', 'isGlobalScript', 'version', 'roleScopeTagIds', 'remediationScriptContent', 'remediationScriptParameters', 'detectionScriptContent', 'highestAvailableVersion'
    $filteredScripts = $remediationScripts.value | Select-Object -Property * -ExcludeProperty $propertiesToRemove

    return ($filteredScripts | ConvertTo-Json -Depth 100) | ConvertFrom-Json
}

function Get-IntuneRemediationScriptContent{
    param(
        [string]$id,
        [string]$folderPath
    )
    $remediationScript = Invoke-MGGraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts/$id" -Method GET
    if (($remediationScript.detectionScriptContent).Length -ne 0) {
        [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($($remediationScript.detectionScriptContent))) | Out-File -Encoding ASCII -FilePath $(Join-Path $folderPath "DetectionScript.ps1")
    }
    if (($remediationScript.remediationScriptContent).Length -ne 0) {
        [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($($remediationScript.remediationScriptContent))) | Out-File -Encoding ASCII -FilePath $(Join-Path $folderPath "RemediationScript.ps1")
    }
    Write-Host "Intune script '$($remediationScript.displayName)' content downloaded."
    Write-Host "Path: $folderPath"
}


###############################################################################################################
# Main ########################################################################################################
###############################################################################################################

# Call the function
$scripts = Get-IntuneRemediationScripts

# Get all scripts in folder
$folders = Get-ChildItem -Path .\remediation-scripts -Directory


# Compare Intune script names with folder names
foreach ($script in $scripts) {
    $scriptName = $script.displayName
    $folderMatch = $folders | Where-Object { $_.Name -eq $scriptName }

    if ($folderMatch) {
        Write-Host "Intune script '$scriptName' has a corresponding folder."
    } else {
        Write-Host "Intune script '$scriptName' does not have a corresponding folder."
        New-Item -Path .\remediation-scripts -Name $scriptName -ItemType Directory
        Write-Host "Intune script '$scriptName' does not have a corresponding folder. Folder created."
        Get-IntuneRemediationScriptContent -id $script.id -folderPath $(Join-Path .\remediation-scripts $scriptName)
        $script | ConvertTo-Yaml | Out-File -Encoding ASCII -FilePath $(Join-Path .\remediation-scripts $scriptName\script.yaml)
    }
}

# Compare folder names with Intune script names
foreach ($folder in $folders) {
    $folderName = $folder.Name
    $scriptMatch = $scripts | Where-Object { $_.displayName -eq $folderName }

    if ($scriptMatch) {
        Write-Host "Folder '$folderName' has a corresponding Intune script."
        # CHeck if yaml file exists
        $yamlFile = Get-ChildItem -Path $folder.FullName -Filter "script.yaml"
        if ($yamlFile) {
            Write-Host "Folder '$folderName' have a corresponding yaml file."
            $yamlScript = Get-Content -Path $yamlFile.FullName | ConvertFrom-Yaml
            # TODO: Comapre scripts

        }else{
            Write-Host "Folder '$folderName' does not have a corresponding yaml file."
            $scriptMatch | ConvertTo-Yaml | Out-File -Encoding ASCII -FilePath $(Join-Path $folder.FullName "script.yaml")
        }
    } else {
        Write-Host "Folder '$folderName' does not have a corresponding Intune script."
    }
}

