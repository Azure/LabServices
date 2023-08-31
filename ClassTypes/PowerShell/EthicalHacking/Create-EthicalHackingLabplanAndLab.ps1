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
.PARAMETER Username
    The password for the local administrator account on the VM.   See https://learn.microsoft.com/azure/virtual-machines/windows/faq#what-are-the-password-requirements-when-creating-a-vm-  
.PARAMETER Location
    Location name for Azure region where the lab plan and lab should reside.  Run `Get-AzLocation | Format-Table` to see all available.
#>

[CmdletBinding()]
param(

    [parameter(Mandatory = $true, HelpMessage = "Username for all VMs")]
    [string]$UserName = "AdminUser",

    [parameter(Mandatory = $true, HelpMessage = "Password for all VMs")]
    [securestring]$Password,

    [parameter(Mandatory = $true, HelpMessage = "Location for lab plan")]
    [string]$Location
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

# Download AzLab module file, import, and then delete the file
if (-not (Get-Module -ListAvailable -Name 'Az')) {
    Import-Module Az -Force 
}

$ClassName = "EthicalHacking"


# Configure parameter names
$rgName     = "rg-$ClassName-$(Get-Random)"
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
        -AdminUserPassword $(ConvertTo-SecureString $Password -AsPlainText -Force) `
        -AdminUserUsername $UserName `
        -AutoShutdownProfileShutdownOnDisconnect Disabled `
        -AutoShutdownProfileShutdownOnIdle None `
        -AutoShutdownProfileShutdownWhenNotConnected Disabled `
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