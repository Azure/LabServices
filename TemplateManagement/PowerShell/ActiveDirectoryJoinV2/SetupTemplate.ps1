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
param()

###################################################################################################

#Install-Module Microsoft.PowerShell.SecretManagement
#Install-Module Microsoft.PowerShell.SecretStore

Import-Module Microsoft.PowerShell.SecretManagement
Import-Module Microsoft.PowerShell.SecretStore

# Password path
$passwordPath = Join-Path $($env:Userprofile) SecretStore.vault.credential

# if password file exists try to login with that
if ($true) {
$pass = Read-Host -AsSecureString -Prompt 'Enter the extension vault password'
# Uses the DPAPI to encrypt the password
$pass | Export-CliXml $passwordPath 

$pass = Import-CliXml $passwordPath
 
}

# Check if store configuration exists
$gssc = Get-SecretStoreConfiguration

if ($gssc) {

    # if not create one
    Set-SecretStoreConfiguration -Scope CurrentUser -Authentication Password -PasswordTimeout (60*60) -Interaction None -Password $pass -Confirm:$false
    
    Register-SecretVault -Name SecretStore -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
 
}

Unlock-SecretStore -Password $pass

# Set Secrets
$djUser = Read-Host -AsSecureString -Prompt 'Enter user to domain join.'
Set-Secret -Name DomainJoinUser -Secret $djUser

$djPass = Read-Host -AsSecureString -Prompt 'Enter password to domain join.'
Set-Secret -Name DomainJoinPassword -Secret $djPass

$djName = Read-Host -AsSecureString -Prompt 'Enter domain join.'
Set-Secret -Name DomainName -Secret $djName

$djAddress = Read-Host -AsSecureString -Prompt 'Enter domain service address.'
Set-Secret -Name DomainServiceAddr -Secret $djAddress

$aadGroupName = Read-Host -AsSecureString -Prompt 'Enter AAD Group name.'
Set-Secret -Name AADGroupName -Secret $aadGroupName

# Copy down files into the Public documents folder
# Setup task scheduler