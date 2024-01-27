#Requires -RunAsAdministrator
#Requires -Version 5.0

<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
.SYNOPSIS
This script verifies configuration of Hyper-V VMs follow best practices for use with Azure Lab Services.
See https://learn.microsoft.com/azure/lab-services/concept-nested-virtualization-template-vm#recommendations for more information
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)][switch]$Force,
    [Parameter(Mandatory = $false)][string]$ConfigFilePath
)

###################################################################################################
#
# PowerShell configurations
#

Set-StrictMode -Version Latest

# NOTE: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.
#       This is necessary to ensure we capture errors inside the try-catch-finally block.
$ErrorActionPreference = "Stop"

# Hide any progress bars, due to downloads and installs of remote components.
$ProgressPreference = "SilentlyContinue"

# Ensure we set the working directory to that of the script.
Push-Location $PSScriptRoot

# Discard any collected errors from a previous execution.
$Error.Clear()

# Configure strict debugging.
Set-PSDebug -Strict

# Configure variables for ShouldContinue prompts
$YesToAll = $Force
$NoToAll = $false

###################################################################################################
#
# Handle all errors in this script.
#

trap {
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    $message = $Error[0].Exception.Message
    if ($message) {
        Write-Host -Object "`nERROR: $message" -ForegroundColor Red
    }

    Write-Host "`nThe script failed to run.`n"

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

###################################################################################################
#
# Class definitions for Hyper-VM configurations
#

class ConfigurationInfo {
    [VmConfiguration[]] $VMConfigurations
    ConfigurationInfo() {
        $this.VMConfigurations = @()
    }
}

class VmConfiguration {
    [string] $Name
    [VmConfigurationProperties] $Properties

}

class VmConfigurationProperties {
    [int]$ProcessorCount
    [VMConfigurationMemoryProperties] $Memory


}

class VMConfigurationMemoryProperties {
    [string] $Startup
    [bool] $DynamicMemoryEnabled
    [string] $Minimum
    [string] $Maximum
}


###################################################################################################
#
# Functions used in this script.
# 

<#
.SYNOPSIS
Converts contents of json file into ConfigurationInfo class that lists expected vCPUs and memory.
See 'vm-config-schema.json' for schema.

.PARAMETER SettingsFilePath
Parameter description

.NOTES
Useful when checking ethical hacking course where vulnerable VMs need less than default vCPUs and memory.

#>
function Get-ConfigurationSettings {
    [CmdletBinding()]
    
    param(
        [string]$SettingsFilePath
    )
    $settings = $null
    if (Test-Path $SettingsFilePath) {
        $settings = return Get-Content -Path $SettingsFilePath -ErrorAction SilentlyContinue | ConvertFrom-Json 
    }
    return [ConfigurationInfo] $settings
}

<#
.SYNOPSIS
Returns VmConfiguration instances with default values for expected configuration of vCPUs and memory.
#>
function Get-DefaultConfigurationSettings {
    [CmdletBinding()]
    [OutputType('VmConfiguration')]
    param(  )

    $defaultConfigString = 
@"
    {
        "Name": "default-vm-config",
        "Properties": {
            "ProcessorCount": 2,
            "Memory": {
                "Startup": "2GB",
                "DynamicMemoryEnabled": true,
                "Minimum": "2GB",
                "Maximum": "4GB"
            }
        }
    }
"@

    Write-Debug "Default configuration: `n$($defaultConfigString)"
    return [VmConfiguration] $($defaultConfigString | ConvertFrom-Json)

}

<#
.SYNOPSIS
Checks property of Hyper-V VM.  If value is not acceptable, property is updated to acceptable value

.PARAMETER vm
Hyper-V VM object

.PARAMETER GetCurrentValueScriptBlock
Optional. Script block that returns the current value of Hyper-V property being checked.
Value used in message when asking user if they want to update property value.

.PARAMETER GetNewValueScriptBlock
Optional. Script block that returns the new value that property will be set to, if current property value is not acceptable.
Value used in message when asking user if they want to update property value.

.PARAMETER IsCurrentValueAcceptableScriptBlock
Returns true if value for current property is acceptable, false otherwise.

.PARAMETER SetValueScriptBlock
Script that sets the property to an acceptable value.

.PARAMETER PropertyName
Name of property being checked. 

.NOTES
This function exists because you cannot set Hyper-V properties through their PowerShell objects.  
You must use Set-VM or Set-VMMemory commandlets
#>
function Set-HypervVmProperty {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)][Microsoft.HyperV.PowerShell.VirtualMachine] $vm,
        [scriptblock]$GetCurrentValueScriptBlock,
        [scriptblock]$GetNewValueScriptBlock,
        [Parameter(Mandatory = $true)][scriptblock]$IsCurrentValueAcceptableScriptBlock,
        [Parameter(Mandatory = $true)][scriptblock]$SetValueScriptBlock,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $isAcceptableValue = & $IsCurrentValueAcceptableScriptBlock

    if (-not $isAcceptableValue) {
         
        #Stop VM, if not done already
        if (($vm | Select-Object -ExpandProperty State) -ne [Microsoft.HyperV.PowerShell.VMState]::Off) {
            if (-not $PSCmdlet.ShouldContinue("Stop VM?  It is required to change $($PropertyName). ", "Stop $($vm.VMName)", [ref] $YesToAll, [ref] $NoToAll )) {
                Write-Host "Did not change $($PropertyName).  VM must be stopped first."
                return
            }

            $vm | Stop-VM -Force -WarningAction Continue          
        }

        #Build detailed prompt string.
        $prompt = ""
        if ($GetCurrentValueScriptBlock) {
            $prompt += " Current value is '$(& $GetCurrentValueScriptBlock)'."
        }
        if ($GetNewValueScriptBlock) {
            $prompt += " New value will be '$(& $GetNewValueScriptBlock)'."
        }

        #Ask user permission before updating property.
        if ($PSCmdlet.ShouldContinue($prompt, "Change value of $($PropertyName)?", [ref] $YesToAll, [ref] $NoToAll)) {     
            & $SetValueScriptBlock
        }
    }
}

<#
.SYNOPSIS
Returns true is current machine is a Windows Server machine and false otherwise.
#>
function Get-RunningServerOperatingSystem {
    [CmdletBinding()]
    param()

    return ($null -ne $(Get-Module -ListAvailable -Name 'servermanager') )
}

<#
.SYNOPSIS
Returns true if DHCP role is installed on Windows Server OS.
#>
function Get-DhcpInstalled {
    if ($(Get-RunningServerOperatingSystem) -and $(Get-WindowsFeature -Name 'DHCP')) {
        return   $($(Get-WindowsFeature -Name 'DHCP') | Select-Object -ExpandProperty Installed)
    }
    else {
        return $false
    }
}

<#
.SYNOPSIS
Returns object for 'Hyper-V Administrator' local group.
#>
function Get-HyperVAdminGroup{
    return Get-LocalGroup | Where-Object { $_.SID -eq "S-1-5-32-578" }
}

<#
.SYNOPSIS
Returns true if user is in the 'Hyper-V Admininstrator' group.
#>
function Get-HypervAdminStatus{
    param(
        [Parameter(Mandatory = $true)][string] $LocalUserName
    )
    
    $hyperVAdminGroup = Get-HyperVAdminGroup
    $isHypervAdmin = @(Get-LocalGroupMember -Group $hyperVAdminGroup | Select-Object -Expand Name) -contains "$($env:COMPUTERNAME)\$($LocalUserName)"
    
    Write-Verbose "$($localUserName) part of Hyper-V Administrators group? $($isHypervAdmin)"
    
    return $isHypervAdmin
}

<#
.SYNOPSIS
Returns true if user is in the local Administrator group.
#>
function Get-LocalAdminStatus{
    param(
        [Parameter(Mandatory = $true)][string] $LocalUserName
    )

    $isAdmin = $null -ne $(Get-WmiObject win32_groupuser |  Where-Object { $_.groupcomponent -like '*"Administrators"' } | Where-Object { $_.PartComponent -like $LocalUserName })
    Write-Verbose "$($localUserName) part of Administrators group? $($isAdmin)"
  
    return $isAdmin
}

<#
.SYNOPSIS
Returns list of local user accounts added to the Host VM.
#>
function Get-AddedLocalUser{
    $addedLocalUsers = @(Get-LocalUser | Where-Object { [int]$($_.SID -split '-' | Select-Object -Last 1) -ge '1000' })

    return $addedLocalUsers
}

###################################################################################################
#
# Main execution block.
#

try {
    Write-Host "Verifying OS"
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) { Write-Error "Script applies to Windows only." }

    # --------------------- Checking USER settings ---------------------------------------------------
    Write-Host "******************************"
    Write-Host "* Checking User Permissions  *"
    Write-Host "******************************"

    # Try to find other users on the machines, if there is one, then ask if they should be added to the "Hyper-V Administrators" group
    $addedLocalUsers = @(Get-AddedLocalUser)
    if ($addedLocalUsers.Count -gt 0) {
 
        foreach ($localUser in $addedLocalUsers) {
            $localUserName = $localUser | Select-Object -ExpandProperty Name
 
            if ($(Get-LocalAdminStatus -LocalUserName $localUserName) -or $(Get-HypervAdminStatus -LocalUserName $localUserName)) {
                Write-Host "Verified user '$($localUserName)' has permissions to use Hyper-V."
            }
            else {
                if ($PSCmdlet.ShouldContinue("User '$($localUserName)' can not use Hyper-V.  Add user to Hyper-V Administrators Group?", "Add user to Hyper-V Administrators Group?", [ref] $YesToAll, [ref] $NoToAll )) {          
                    Add-LocalGroupMember -Group $(Get-HyperVAdminGroup) -Member $localUser
                    Write-Host "$($localUserName) added to Hyper-V Administrators group."   
                }  
            }
        }
    }
    Write-Host "Permission check completed.`n"

    # --------------------- Checking HYPER-V VM settings ---------------------------------------------------
   

    if ($ConfigFilePath) {
        $configs = Get-ConfigurationSettings -SettingsFilePath $ConfigFilePath
    }
    else {
        $configs = New-Object ConfigurationInfo
    }

    $vms = @(Get-VM)

    if ($vms.Count -gt 0) {

        Write-Host "******************************"
        Write-Host "*    Testing HYPER-V VMs     *"
        Write-Host "******************************"


        # Warn if any VMs are in saved state
        $savedStateVMs = @($vms | Where-Object { $_.State -eq "Saved" })
        if ($savedStateVMs) {
            Write-Warning "Found VM(s) that are in a saved state. VM may fail to start if processor of the Azure VM changes.`n`t$($savedStateVMs -join '`n`t')"
            if ($PSCmdlet.ShouldContinue("Found VM(s) that are in a saved state. VM may fail to start if processor of the Azure VM changes.`n`t$($savedStateVMs -join '`n`t').", "Start and ShutDown Hyper-V VMs?", [ref] $YesToAll, [ref] $NoToAll )) {
                foreach ($vm in $savedStateVMs) {
                    $vm | Start-VM -WarningAction Continue
                    $vm | Stop-VM -Force -WarningAction Continue
                    Write-Verbose "Hyper-V VM $($vm.VMName) started and stopped."
                }
            }
        }

        # Premptively stop all VMs.  Most settings require the VM to be stopped before the setting can be updated.
        $runningStateVMs = @($vms | Where-Object { $_.State -eq "Running" })
        if ($runningStateVMs) {
            if ($PSCmdlet.ShouldContinue("Found VM(s) that are running. VMs must be shutdown before settings are updated.", "ShutDown Hyper-V VMs?", [ref] $YesToAll, [ref] $NoToAll )) {
                foreach ($vm in $runningStateVMs) {
                    $vm | Stop-VM -Force -WarningAction Continue
                    Write-Verbose "Hyper-V VM $($vm.VMName) stopped."
                }
            }
        }

        foreach ($vm in $vms) {
            $vmName = $vm.VMName
            Write-Host "============================="
            Write-Host "`t$($vmName)"
            Write-Host "============================="

            #Check if there are non-default config settings for VM
            $currentConfig = $configs.VMConfigurations | Where-Object { $_.Name -eq $vmName }
            if (-not $currentConfig) {
                $currentConfig = Get-DefaultConfigurationSettings
                $currentConfig.Name = $vmName
            }
            Write-Verbose "Expected Configuration: `n$($currentConfig | ConvertTo-Json)"
    

            Write-Host "Verifying: AutomaticStopAction==ShutDown"
            $vm | Set-HypervVmProperty -PropertyName "AutomaticStopAction" `
                -GetCurrentValueScriptBlock { $vm | Select-Object -ExpandProperty AutomaticStopAction } `
                -GetNewValueScriptBlock { [Microsoft.HyperV.PowerShell.StopAction]::ShutDown } `
                -IsCurrentValueAcceptableScriptBlock { $($vm | Select-Object -ExpandProperty AutomaticStopAction ) -eq [Microsoft.HyperV.PowerShell.StopAction]::ShutDown } `
                -SetValueScriptBlock { $vm | Set-VM -AutomaticStopAction ShutDown } 

            $processorCount = $vm | Select-Object -ExpandProperty ProcessorCount
            $expectedProcessorCount = $currentConfig.Properties.ProcessorCount
            $expectedProcessorCount = [math]::Max(1, $expectedProcessorCount)
            $expectedProcessorCount = [math]::Min($expectedProcessorCount, $env:NUMBER_OF_PROCESSORS)
            Write-Host "Verifying: ProcessorCount >= $($expectedProcessorCount)"
            $vm | Set-HypervVmProperty -PropertyName "ProcessorCount" `
                -GetCurrentValueScriptBlock {$processorCount} `
                -GetNewValueScriptBlock {$expectedProcessorCount} `
                -IsCurrentValueAcceptableScriptBlock { $processorCount -ge $expectedProcessorCount } `
                -SetValueScriptBlock {  $vm | Set-VM -ProcessorCount $expectedProcessorCount } 

            $assignedMemory = $vm | Get-VMMemory
            $startupMemory = $assignedMemory | Select-Object -ExpandProperty Startup
            $expectedStartupMemory = Invoke-Expression($currentConfig.Properties.Memory.Startup) #Invoke-Expression required to convert "1GB" to 1GB
            Write-Host "Verifying: Memory.Startup >= $($expectedStartupMemory)"
            $vm | Set-HypervVmProperty -PropertyName "Memory - Startup" `
                -GetCurrentValueScriptBlock { "$($startupMemory / 1GB) GB" } `
                -GetNewValueScriptBlock {"$($expectedStartupMemory / 1GB) GB"} `
                -IsCurrentValueAcceptableScriptBlock { $startupMemory -ge $expectedStartupMemory } `
                -SetValueScriptBlock { $vm | Set-VMMemory -Startup  $expectedStartupMemory } 

            $dynamicMemoryEnabled = $assignedMemory | Select-Object -ExpandProperty DynamicMemoryEnabled
            $expectedDynamicMemoryEnabled = $currentConfig.Properties.Memory.DynamicMemoryEnabled
            Write-Host "Verifying: Memory.DynamicMemoryEnabled == $($expectedDynamicMemoryEnabled)"
            $vm | Set-HypervVmProperty -PropertyName "Memory - Dynamic Memory Enabled" `
                -GetCurrentValueScriptBlock { $dynamicMemoryEnabled } `
                -GetNewValueScriptBlock { $expectedDynamicMemoryEnabled } `
                -IsCurrentValueAcceptableScriptBlock { $dynamicMemoryEnabled -eq $expectedDynamicMemoryEnabled } `
                -SetValueScriptBlock { $vm | Set-VMMemory -DynamicMemoryEnabled $expectedDynamicMemoryEnabled } 
                
            if ($assignedMemory | Select-Object -ExpandProperty DynamicMemoryEnabled) {
                $desiredMinimumMemory = Invoke-Expression($currentConfig.Properties.Memory.Minimum)
                Write-Host "Verifying: Memory.DynamicMemory.Minimum >= $desiredMinimumMemory"
                $vm | Set-HypervVmProperty -PropertyName "Dynamic Memory - Minimum" `
                    -GetCurrentValueScriptBlock { "$($($assignedMemory | Select-Object -ExpandProperty Minimum) / 1GB) GB" } `
                    -GetNewValueScriptBlock { "$($desiredMinimumMemory / 1GB) GB" } `
                    -IsCurrentValueAcceptableScriptBlock { $($assignedMemory | Select-Object -ExpandProperty Minimum ) -ge $desiredMinimumMemory } `
                    -SetValueScriptBlock { $vm | Set-VMMemory -MinimumBytes  $desiredMinimumMemory } 

                $desiredMaximumMemory = Invoke-Expression($currentConfig.Properties.Memory.Maximum)
                Write-Host "Verifying: Memory.DynamicMemory.Maximum >= $desiredMaximumMemory"
                $vm | Set-HypervVmProperty -PropertyName "Dynamic Memory - Maximum" `
                    -GetCurrentValueScriptBlock { $assignedMemory | Select-Object -ExpandProperty Maximum } `
                    -GetNewValueScriptBlock { "$($desiredMaximumMemory / 1GB) GB" } `
                    -IsCurrentValueAcceptableScriptBlock { $($assignedMemory | Select-Object -ExpandProperty Maximum ) -ge $desiredMaximumMemory } `
                    -SetValueScriptBlock { $vm | Set-VMMemory -MaximumBytes  $desiredMaximumMemory } 
            }

            # Verify disk is vhdx not vhd
            $hardDriveDisks = @($vm | Get-VMHardDiskDrive)
            foreach ($hardDriveDisk in $hardDriveDisks) {
                $diskPath = $hardDriveDisk | Select-Object -ExpandProperty Path
                $diskName = [System.IO.Path]::GetFileNameWithoutExtension($diskPath)
                Write-Host "Verifying: HardDriveDisks.$diskName.VMType == Dynamic"

                $vm | Set-HypervVmProperty -PropertyName "Disk '$diskName' - VhdType" `
                    -GetCurrentValueScriptBlock { Get-VHD $diskPath | Select-Object -ExpandProperty VhdFormat } `
                    -GetNewValueScriptBlock { "VHDX" } `
                    -IsCurrentValueAcceptableScriptBlock { $(Get-VHD $diskPath | Select-Object -ExpandProperty VhdFormat) -eq "VHDX" } `
                    -SetValueScriptBlock { 
                        $newDiskPath = Join-Path $([System.IO.Path]::GetDirectoryName($diskPath)) "$($diskName).vhdx"
                        if (Test-Path $newDiskPath) {
                            Write-Error "Unable to convert '$($diskPath)' to '$($newDiskPath). '$($newDiskPath) exists." -ErrorAction Continue
                        }
                        else {
                            $controllerLocation = $hardDriveDisk | Select-Object -ExpandProperty ControllerLocation
                            $controllerNumber = $hardDriveDisk | Select-Object -ExpandProperty ControllerNumber
                            $controllerType = $hardDriveDisk | Select-Object -ExpandProperty ControllerType
                        
                            $hardDriveDisk | Remove-VMHardDiskDrive
                            Convert-VHD -Path $diskPath -DestinationPath $newDiskPath -VHDType Dynamic 

                            Add-VMHardDiskDrive -VMName $vm.VMName -Path $newDiskPath -ControllerLocation $controllerLocation -ControllerType $controllerType -ControllerNumber $controllerNumber                    
                        }

                    }
            }

            Write-Host "Testing Hyper-V VM $($vmName) completed.`n"
        }

        # --------------------- Checking HOST VM settings ---------------------------------------------------
        Write-Host "*************************************"
        Write-Host "*        Checking HOST VM Settings   *"
        Write-Host "*************************************"

        Write-Host "Checking network settings."
     
       if (Get-RunningServerOperatingSystem) {         
            if (Get-DhcpInstalled) {
                $warningText = 
@"
    Installing DHCP role on an Azure VM is not a supported scenario.
    See https://learn.microsoft.com/azure/virtual-network/virtual-networks-faq#can-i-deploy-a-dhcp-server-in-a-vnet
    
    It is recommended to unistall the DHCP role and modify network adapter settings for Hyper-V VMs for internet connectivity.
"@    
            Write-Warning $warningText
            }            
        }

        Write-Host "Checking Host VM disk space requirements."

        $systemDriveLetter = Get-CimInstance -ClassName CIM_OperatingSystem | Select-Object -expand SystemDrive
        if ($systemDriveLetter) {
            $freeSpaceInGib = Get-PSDrive -Name $systemDriveLetter.Trim(":") | Select-Object -ExpandProperty Free
            if ($freeSpaceInGib) {
                if ($freeSpaceInGib -le 4GB) {
                    Write-Warning "Free space on $($systemDriveLetter) disk running low.  Clear up space to avoid issues starting VM in the future."
                }
                elseif ($freeSpaceInGib -le 1GB) {
                    Write-Error "Free space on $($systemDriveLetter) disk < 1GB.  Clear up space immediately as VM requires free diskspace to start succesfully."
                }
            }
        }

        Write-Host "Host VM check completed.`n"


        Write-Host "******************************"
        Write-Host "*           RESULTS          *"
        Write-Host "******************************"

        if ($freeSpaceInGib){
            Write-Host "============================="
            Write-Host "Host VM: $($env:computername)"
            Write-Host "============================="
            Write-Output "`tFree disk space: $($freeSpaceInGib / 1GB) GB"
        }

        # List current status
        foreach ($vm in $vms) {
            Write-Host "============================="
            Write-Host "`Hyper-V VM: $($vm.VMName)"
            Write-Host "============================="
            Write-Host "`tState: $($vm | Select-Object -ExpandProperty State)"
            Write-Host "`tAutomaticStopAction: $($vm | Select-Object -ExpandProperty AutomaticStopAction)"
            Write-Host "`tvCPU(s): $($vm | Select-Object -ExpandProperty ProcessorCount)"
            Write-Host "`tMemory - Startup: $($($vm | Get-VMMemory | Select-Object -ExpandProperty Startup)/1GB) GB"
            Write-Host "`tMemory - Dynamic Memory Enabled: $($vm | Get-VMMemory | Select-Object -ExpandProperty DynamicMemoryEnabled)"
            Write-Host "`tMemory - Minimum: $($($vm | Get-VMMemory | Select-Object -ExpandProperty Minimum)/1GB) GB"
            Write-Host "`tMemory - Maximum: $($($vm | Get-VMMemory | Select-Object -ExpandProperty Maximum)/1GB) GB"
            $hardDriveDisks = @($vm | Get-VMHardDiskDrive)
            foreach ($hardDriveDisk in $hardDriveDisks) {
                $diskPath = $hardDriveDisk | Select-Object -ExpandProperty Path
                Write-Host "`tDisk - $([System.IO.Path]::GetFileNameWithoutExtension($diskPath)): $(Get-VHD $diskPath | Select-Object -ExpandProperty VhdFormat)"
            }

        }
        Write-Host ""

        Write-Host "******************************"
        if ($PSCmdlet.ShouldContinue("Done checking Hyper-V VMs.  Restart all Hyper-V VMs?", "Restart Hyper-V VMs?", [ref] $YesToAll, [ref] $NoToAll )) {
            foreach ($vm in $vms) {
                $vm | Stop-VM -Force -WarningAction SilentlyContinue
                $vm | Start-VM -WarningAction Continue
                Write-Verbose "Restarted $($vm.VMName)."
            }
        }
    } 
}
finally {
    # Restore system to state prior to execution of this script.
    Pop-Location
}
