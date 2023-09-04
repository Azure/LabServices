<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
.SYNOPSIS
    Creates a Azure Lab Services lab plan and lab that can be used to create an ethical hacking lab.
.DESCRIPTION
    Creates a Azure Lab Services lab plan and lab that can be used to create an ethical hacking lab.
.PARAMETER Username
    The username for the local administrator account on the VM.
.PARAMETER Password
    The password for the local administrator account on the VM.   See https://learn.microsoft.com/azure/virtual-machines/windows/faq#what-are-the-password-requirements-when-creating-a-vm-  
.PARAMETER Location
    Location name for Azure region where the lab plan and lab should reside.  Run `Get-AzLocation | Format-Table` to see all available.
.PARAMETER ClassName
    Name for class.  Must be a valid Azure Resource name.  Defaults to 'EthicalHacking'
    #>

[CmdletBinding()]
param(

    [parameter(Mandatory = $true, HelpMessage = "Username for all VMs")]
    [string]$UserName = "AdminUser",

    [parameter(Mandatory = $true, HelpMessage = "Password for all VMs")]
    [securestring]$Password,

    [parameter(Mandatory = $true, HelpMessage = "Location for lab plan")]
    [string]$Location,

    [parameter(Mandatory = $false, HelpMessage = "Name of the class")]
    $ClassName = "EthicalHacking"
)

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
# Main execution block.
#

if ((Get-Module -ListAvailable -Name 'Az.Accounts') -and
    (Get-Module -ListAvailable -Name 'Az.Resources') -and
    (Get-Module -ListAvailable -Name 'Az.LabServices')) {
        Import-Module -Name Az.Accounts
        Import-Module -Name Az.Resources
        Import-Module -Name Az.LabServices
}
else {
    Write-Error "Unable to run script, Az modules are missing.  Please install them via 'Install-Module -Name Az -Force' from an elevated command prompt"
    exit -1
}

# Check password
if ( -not ($Password -match "[A-Za-z0-9_@]{16,}")){
    Write-Error "Password must be 16 characters long and only contain following characters: A-Z a-z 0-9 _ @ "
    exit -1
}

$ClassName = $ClassName.Trim().Replace(' ','-')

# Configure parameter names
$rgName     = "rg-$ClassName-$(Get-Random)".ToLower()
$labPlanName     = "lp-$ClassName$(Get-Random)"
$labName    =  "$($ClassName)Lab"

# Create resource group
Write-Host "Creating resource group $rgName"
$rg = New-AzResourceGroup -Name $rgName -Location $Location
    
# Create Lab Plan
Write-Host "Creating lab plan $labPlanName"
$labPlan  = New-AzLabServicesLabPlan -ResourceGroupName $rgName -Name $labPlanName -Location $Location -AllowedRegion @($Location)

# Ensure that image needed for the VM is available
$imageName = "Windows Server 2022 Datacenter (Gen2)"
$sku = "2022-datacenter-g2"
Write-Host "Locating '$imageName' image for use in template virtual machine"
$imageObject = $labPlan | Get-AzLabServicesPlanImage | Where-Object {$_.DisplayName -EQ $imageName -and $_.Sku -EQ $sku -and (-not [string]::IsNullOrEmpty($_.EnabledState))} | Where-Object -Property EnabledState -eq "Enabled"

if($null -eq $imageObject) {
    Write-Error "Image '$imageName' was not found in the gallery images. Couldn't create lab $labName."
    exit -1
}

# Create lab using the lab plan
Write-Host "Creating $labName with '$($imageObject.Name)' image"
Write-Warning "  Warning: Creating template vm may take up to 20 minutes."
$lab = New-AzLabServicesLab -Name $labName `
        -ResourceGroupName $rgName `
        -Location $Location `
        -LabPlanId $labPlan.Id.ToString() `
        -AdditionalCapabilityInstallGpuDriver Disabled `
        -AdminUserPassword $Password `
        -AdminUserUsername $UserName `
        -AutoShutdownProfileShutdownOnDisconnect Enabled `
        -AutoShutdownProfileDisconnectDelay $(New-Timespan) `
        -AutoShutdownProfileShutdownOnIdle "LowUsage" `
        -AutoShutdownProfileIdleDelay $(New-TimeSpan -Minutes 15) `
        -AutoShutdownProfileShutdownWhenNotConnected Enabled `
        -AutoShutdownProfileNoConnectDelay $(New-TimeSpan -Minutes 15) `
        -ConnectionProfileClientRdpAccess Public `
        -ConnectionProfileClientSshAccess None `
        -ConnectionProfileWebRdpAccess None `
        -ConnectionProfileWebSshAccess None `
        -Description "Ethical Hacking lab." `
        -ImageReferenceOffer $imageObject.Offer.ToString() `
        -ImageReferencePublisher $imageObject.Publisher.ToString() `
        -ImageReferenceSku $imageObject.Sku.ToString() `
        -ImageReferenceVersion $imageObject.Version.ToString() `
        -SecurityProfileOpenAccess Disabled `
        -SkuCapacity 2 `
        -SkuName "Classic_Dsv4_4_16GB_128_P_SSD" `
        -Title $labName `
        -VirtualMachineProfileCreateOption "TemplateVM" `
        -VirtualMachineProfileUseSharedPassword Enabled

# If lab created, perform next configuration
if($null -eq $lab) {
    Write-Error "Lab failed to create."
    exit -1
}

Write-Host "Done! Lab plan and lab have been created." -ForegroundColor Green