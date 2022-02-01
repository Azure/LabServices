[CmdletBinding()]
param(
    [parameter(Mandatory = $false)]
    [string]$Email,

    [parameter(Mandatory = $false, HelpMessage = "Default username for all VMs")]
    [string]$Username = "AdminUser",

    [parameter(Mandatory = $false, HelpMessage = "Default password for all VMs")]
    [string]$Password = "P@ssword1!",

    [parameter(Mandatory = $false, HelpMessage = "Default location for lab plan")]
    [string]$Location = "centralus",

    [parameter(Mandatory = $false, HelpMessage = "Default Base for lab plan, lab, and resource group names")]
    [string]$ClassName = "EthicalHacking"
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

Import-Module Az.LabServices -Force


# Configure parameter names
$rgName     = "$($ClassName)RG_" + (Get-Random)
$labPlanName     = "$($ClassName)Acct_" + (Get-Random)
$labName    =  "$($ClassName)Lab"

# Create resource group
Write-Host "Creating resource group $rgName"
$rg = New-AzResourceGroup -Name $rgName -Location $Location
    
# Create Lab Account
Write-Host "Creating lab plan $labPlanName"
$labPlan  = New-AzLabServicesLabPlan -ResourceGroupName $rgName -Name $labPlanName -Location $Location -AllowedRegion @($Location)

# Ensure that image needed for the VM is available
$imageName = "Windows Server 2022 Datacenter"
$sku = "2022-DataCenter-g2"
Write-Host "Locating '$imageName' image for use in template virtual machine"
$imageObject = $labPlan | Get-AzLabServicesPlanImage | Where-Object {$_.DisplayName -EQ $imageName -and $_.Sku -EQ $sku -and (-not [string]::IsNullOrEmpty($_.EnabledState))} | Where-Object -Property EnabledState -eq "Enabled"

if($null -eq $imageObject) {
    Write-Error "Image '$imageName' was not found in the gallery images. No lab was created within lab account $labPlanName."
    exit -1
}

# Create lab on the lab account
Write-Host "Creating $labName with '$($imageObject.Name)' image"
Write-Warning "  Warning: Creating template vm may take up to 20 minutes."
$lab = New-AzLabServicesLab -Name $labName `
        -ResourceGroupName $rgName `
        -Location $Location `
        -LabPlanId $labPlan.Id.ToString() `
        -AdditionalCapabilityInstallGpuDriver Disabled `
        -AdminUserPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
        -AdminUserUsername "adminUser" `
        -AutoShutdownProfileShutdownOnDisconnect Disabled `
        -AutoShutdownProfileShutdownOnIdle None `
        -AutoShutdownProfileShutdownWhenNotConnected Disabled `
        -ConnectionProfileClientRdpAccess Public `
        -ConnectionProfileClientSshAccess None `
        -ConnectionProfileWebRdpAccess None `
        -ConnectionProfileWebSshAccess None `
        -Description "Ethical Hacking Lab." `
        -ImageReferenceOffer $imageObject.Offer.ToString() `
        -ImageReferencePublisher $imageObject.Publisher.ToString() `
        -ImageReferenceSku $imageObject.Sku.ToString() `
        -ImageReferenceVersion $imageObject.Version.ToString() `
        -SecurityProfileOpenAccess Disabled `
        -SkuCapacity 2 `
        -SkuName "Classic_Fsv2_2_4GB_128_S_SSD" `
        -Title $labName `
        -VirtualMachineProfileCreateOption "TemplateVM" `
        -VirtualMachineProfileUseSharedPassword Enabled

# If lab created, perform next configuration
if($null -eq $lab) {
    Write-Error "Lab failed to create."
    exit -1
}

Write-Host "Lab has been created."

# Stop the VM image so that it is not costing the end user
Write-Host "Stopping the template VM within $labName"
Write-Warning "  Warning: This could take some time to stop the template VM."
$labTemplateVM = Get-AzLabServicesTemplateVM -Lab $lab
if ($labTemplateVM.State -ne "Stopped") {
    Stop-AzLabServicesVm -VM $labTemplateVM
}
# Give permissions to optional email address user
if ($Email) 
{
    #grant access to labs if an educator email address was provided
    Write-Host "Retrieving user data for $Email"
    $userId = Get-AzADUser -UserPrincipalName $Email | Select-Object -expand Id

    if($null -eq $userId) {
        Write-Warning "$Email is NOT an user in your AAD. Could not add permissions for this user to the lab account and lab."
    }
    else
    {
        Write-Host "Adding $Email as a Reader to the lab account"
        New-AzRoleAssignment -ObjectId $userId -RoleDefinitionName 'Reader' -ResourceGroupName $rg.ResourceGroupName -ResourceName $labPlan.Name -ResourceType $labPlan.Type
        Write-Host "Adding $Email as a Contributor to the lab"
        New-AzRoleAssignment -ObjectId $userId -RoleDefinitionName 'Contributor' -Scope $lab.id
    }
}

Write-Host "Done!" -ForegroundColor 'Green'