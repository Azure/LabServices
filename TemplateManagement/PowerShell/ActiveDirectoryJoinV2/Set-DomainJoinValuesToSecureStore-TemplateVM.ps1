<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
.SYNOPSIS
This script is part of the scripts chain for joining a student VM to an Active Directory domain. It renames the computer with a unique ID. Then it schedules the actual join script to run after reboot.
.LINK https://docs.microsoft.com/en-us/azure/lab-services/classroom-labs/how-to-connect-peer-virtual-network
#>


[CmdletBinding()]
param(
    [Parameter(Mandatory,
    ValueFromPipeline=$true, 
    ValueFromPipelineByPropertyName=$true,
    HelpMessage="Domain user that has join rights.")]
    [ValidateNotNullOrEmpty()]
    [string]
    $DomainJoinUserName,

    [Parameter(Mandatory,
    ValueFromPipeline=$true, 
    ValueFromPipelineByPropertyName=$true,
    HelpMessage="Domain user password.")]
    [ValidateNotNullOrEmpty()]
    [securestring]
    $DomainJoinPassword,

    [Parameter(Mandatory,
    ValueFromPipeline=$true, 
    ValueFromPipelineByPropertyName=$true,
    HelpMessage="Domain name to join.")]
    [ValidateNotNullOrEmpty()]
    [string]
    $DomainName,

    [Parameter(Mandatory,
    ValueFromPipeline=$true, 
    ValueFromPipelineByPropertyName=$true,
    HelpMessage="Lab AAD group of students.")]
    [ValidateNotNullOrEmpty()]
    [string]
    $AADGroupName,

    [Parameter(Mandatory,
    ValueFromPipeline=$true, 
    ValueFromPipelineByPropertyName=$true,
    HelpMessage="Lab prefix for machine names.")]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(3,7)]
    [string]
    $LabPrefix,

    [Parameter(Mandatory,
    ValueFromPipeline=$true, 
    ValueFromPipelineByPropertyName=$true,
    HelpMessage="Password for the local secure vault.")]
    [ValidateNotNullOrEmpty()]
    [securestring]
    $SecureVaultPassword
)

###################################################################################################

function Write-LogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )
 
    # Get the current date
    $TimeStamp = Get-Date -Format o

    # Add Content to the Log File
    $Line = "$TimeStamp - $Message"
    Add-content -Path $Logfile -Value $Line -ErrorAction SilentlyContinue
    Write-Output $Line
}


Import-Module Microsoft.PowerShell.SecretManagement
Import-Module Microsoft.PowerShell.SecretStore

$LogFile = Join-Path $($env:Userprofile) "DJLog$(Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }).txt"
New-Item -Path $logFile -ItemType File

# Check Windows 10 / 11 Operating system
if (!([System.Environment]::OSVersion.Version.Major -match "10" -or [System.Environment]::OSVersion.Version.Major -match "11")) {
    Write-LogFile "Requires Windows 10 or Windows 11."
    exit
}

# Check if template
$MetaDataHeaders = @{"Metadata"="true"}
$vminfo = Invoke-RestMethod -Method GET -uri "http://169.254.169.254/metadata/instance?api-version=2018-10-01" -Headers $MetaDataHeaders

if (!($vminfo.compute.vmScaleSetName -match "template")){
    Write-Log "SaveDomainJoinValuesToSecureStore-TemplateVM script was not run on a template vm."
    exit
}

# Password path
$passwordPath = Join-Path $($env:Userprofile) SecretStore.vault.credential

# if password file exists try to login with that
if (!(Test-Path $passwordPath)) {
    # Uses the DPAPI to encrypt the password
    $SecureVaultPassword | Export-CliXml $passwordPath 
     
}

$pass = Import-CliXml $passwordPath

$vault = Get-SecretVault
if (!$vault) {
    # Configure secret store and create vault
    Set-SecretStoreConfiguration -Scope CurrentUser -Authentication Password -PasswordTimeout (60*60) -Interaction None -Password $pass -Confirm:$false
    Register-SecretVault -Name SecretStore -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
}
Unlock-SecretStore -Password $pass

# Set Secrets
Set-Secret -Name DomainJoinUser -Secret $DomainJoinUserName

Set-Secret -Name DomainJoinPassword -SecureStringSecret $DomainJoinPassword 

Set-Secret -Name DomainName -Secret $DomainName

Set-Secret -Name AADGroupName -Secret $AADGroupName

Set-Secret -Name LabId -Secret $LabPrefix

# Copy down files into the Public documents folder
# TODO set the correct final location
Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/LabServices/domainjoinv2/TemplateManagement/PowerShell/ActiveDirectoryJoinV2/Join-Domain-StudentVM.ps1 -OutFile C:\Users\Public\Documents\Join-Domain-StudentVM.ps1

