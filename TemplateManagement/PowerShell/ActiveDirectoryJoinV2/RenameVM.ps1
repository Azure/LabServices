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

# Default exit code
$ExitCode = 0

try {

    $ErrorActionPreference = "Stop"

    Import-Module Microsoft.PowerShell.SecretManagement
    Import-Module Microsoft.PowerShell.SecretStore
   
    # Setup Log file
    $LogFile = Join-Path $($env:Userprofile) "DJLog$(Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }).txt"
    New-Item -Path $logFile -ItemType File

    # Unlock vault
    $passwordPath = Join-Path $($env:Userprofile) SecretStore.vault.credential
    $pass = Import-CliXml $passwordPath
    Unlock-SecretStore -Password $pass

    # Check IP address for template
    $currentIp = $((Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin DHCP).IPAddress)
    if ($currentIp -ieq $(Get-Secret -Name TemplateIP -AsPlainText)){
        Write-LogFile "Template VM IP, exitting."
        exit
    }

    # Check if vm renamed 
    $computerName = (Get-WmiObject Win32_ComputerSystem).Name
    Write-LogFile "Rename VM section."

    if ($computerName -match 'lab000') {
        
        # Get lab id
        $LabPrefix = Get-Secret -Name LabId -AsPlainText

        # Generate a new unique name for this computer
        $newComputerName = $($LabPrefix + "-$(Get-Random)").Substring(0,14)
        
        Write-LogFile "Renaming the computer '$env:COMPUTERNAME' to '$newComputerName'"
        Rename-Computer -ComputerName $env:COMPUTERNAME -NewName $newComputerName -Force
        Write-LogFile "Local Computer name will be changed to '$newComputerName' -- after restarting the vm."
        $requireRename = $true
        
    }

    Write-LogFile "Clean up section."
    Remove-Item -Path $passwordPath -Force
    Write-LogFile "Restarting vm"
    Restart-Computer -Force

}
catch
{
    $message = $Error[0].Exception.Message
    if ($message) {
        Write-LogFile "`nERROR: $message"
    }

    Write-LogFile "`nThe script failed to run.`n"

    # Important note: Throwing a terminating error (using $ErrorActionPreference = "stop") still returns exit 
    # code zero from the powershell script. The workaround is to use try/catch blocks and return a non-zero 
    # exit code from the catch block. 
    $ExitCode = -1
}

finally {

    Write-LogFile "Exiting with $ExitCode" 
    exit $ExitCode
}