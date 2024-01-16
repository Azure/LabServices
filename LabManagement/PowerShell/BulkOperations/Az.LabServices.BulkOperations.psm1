
# Error if Az.LabServices module not loaded
#if (-not (Get-Command -Name "New-AzLabServicesLab" -ErrorAction SilentlyContinue)) {
#    Write-Error "You need to import the module Az in your script (i.e. Import-Module ../Az -Force )"
#}

# Install the ThreadJob module if the command isn't available
if (-not (Get-Command -Name "Start-ThreadJob" -ErrorAction SilentlyContinue)) {
    Install-Module -Name ThreadJob -Scope CurrentUser -Force
}
# Install the Az.LabServices module if the command isn't available
if (-not (Get-Command -Name "Get-AzLabServicesLab" -ErrorAction SilentlyContinue)) {
    Install-Module -Name Az.LabServices -Scope CurrentUser -Force
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Validate-SkuName{
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Sku,

        [parameter(Mandatory = $true)]
        [string] $labLocation
        )

    # We look up the correct size from the API, this way user can give us size or name
    $subscriptionId = (Get-AzContext).Subscription.Id
    $allSkus = (Invoke-AzRestMethod -Uri https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.LabServices/skus?api-version=2022-08-01 | Select-Object -Property "Content" -ExpandProperty Content | ConvertFrom-Json).value

    # Match the provided sku by either the name, size, and locations property
    # For example:
    # resourceType : labs
    # name         : Basic
    # tier         : Classic
    # size         : Fsv2_2_4GB_128_S_SSD
    # family       : Fsv2
    # locations    : {eastus2}
    # locationInfo : {@{location=eastus2; zones=System.Object[]; zoneDetails=System.Object[]}}
    # capacity     : @{minimum=0; maximum=400; default=1; scaleType=Automatic}
    # capabilities : {@{name=vCPUs; value=2}, @{name=MemoryGB; value=4}, @{name=StorageGB; value=128}, @{name=StorageType; value=StandardSSD}...}
    # restrictions : {}
    $allMatchedSkus = $allSkus | Where-Object {($_.name -ieq $Sku -or $_.size -ieq $Sku) -and $_.locations -ieq $labLocation}
   
    Write-Host "Validating provided VM size. Provided SKU: $($Sku) Lab region: $labLocation."
    if (@($allMatchedSkus).Count -eq 0) {
        $allSkus | Out-File -FilePath ".\AzLabBulkDeploySkuList.txt"
        Write-Error "Failed to find a matching VM SKU.  Provided SKU: $($Sku) Lab region: $labLocation.  Verify that the provided SKU is a valid VM SKU name or size, and that the SKU is available in the same location as the lab's region. See .\AzLabBulkDeploySkuList.txt for list of valid SKUs for your subscription."
        return
    }
    else {
        # There may be duplicate skus, so we need to pick the first one
        $matchedSku = $allMatchedSkus | Select-Object -First 1
        return "$($matchedSku.tier)_$($matchedSku.size)"
    }
}

function Import-LabsCsv {
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $CsvConfigFile
    )

    function Import-Schedules {
        param($schedules)

        $file = "./$schedules.csv"

        $scheds = Import-Csv $file
        $scheds | Foreach-Object {
            $_.WeekDays = ($_.WeekDays.Split(',')).Trim()
        }
        return $scheds
    }

    $labs = Import-Csv -Path $CsvConfigFile

    # Make all the resource groups lower case
    $labs | ForEach-Object {$_.ResourceGroupName = $_.ResourceGroupName.ToLower()}

    Write-Verbose ($labs | Format-Table | Out-String)

    if ($labs[0].PSObject.Properties['LabAccountName']) {
        # Add alias for Lab AccountName
        $labs | Where-Object {$_.LabAccountName} | Add-Member -MemberType AliasProperty -Name LabPlanName -Value LabAccountName -PassThru
    }
    # Validate that if a resource group\lab plan appears more than once in the csv, that it also has the same SharedGalleryId and EnableSharedGalleryImages values.
    $plan = $labs | Select-Object -Property ResourceGroupName, LabPlanName, SharedGalleryId, EnableSharedGalleryImages, Tags | Sort-Object -Property ResourceGroupName, LabPlanName
    $planNames = $plan | Select-Object -Property ResourceGroupName, LabPlanName -Unique
  
    foreach ($planName in $planNames){
        $matchplan = $plan | Where-Object {$_.ResourceGroupName -eq $planName.ResourceGroupName -and $_.LabPlanName -eq $planName.LabPlanName}
        $firstPlan = $matchplan[0]
  
        $mismatchSIGs = $matchplan | Where-Object {$_.SharedGalleryId -ne $firstPlan.SharedGalleryId -or $_.EnableSharedGalleryImages -ne $firstPlan.EnableSharedGalleryImages}
        $mismatchSIGs | Foreach-Object {
            $msg1 = "SharedGalleryId - Expected: $($firstPlan.SharedGalleryId) Actual: $($_.SharedGalleryId)"
            $msg2 = "EnabledSharedGalleryImages - Expected: $($firstPlan.EnableSharedGalleryImages) Actual: $($_.EnableSharedGalleryImages)"
            Write-Error "Lab plan $planName SharedGalleryId and EnableSharedGalleryImages values are not consistent. $msg1. $msg2."
        }
    }

    # Check tags match per lab plan
    foreach ($planName in $planNames){
        $matchplan = $plan | Where-Object {$_.ResourceGroupName -eq $planName.ResourceGroupName -and $_.LabPlanName -eq $planName.LabPlanName}
        $firstPlan = $matchplan[0]
  
        $mismatchSIGs = $matchplan | Where-Object {$_.Tags -ne $firstPlan.Tags}
        $mismatchSIGs | Foreach-Object {
            $msg1 = "Tags - Expected: $($firstPlan.Tags) Actual: $($_.Tags)"
            Write-Error "Lab plan $planName Tags values are not consistent. $msg1."
        }
    }

    $labs | ForEach-Object {

        # First thing, we need to save the original properties in case they're needed later (for export)
        Add-Member -InputObject $_ -MemberType NoteProperty -Name OriginalProperties -Value $_.PsObject.Copy()
        $labPlan = Get-AzLabServicesLabPlan -ResourceGroupName $_.ResourceGroupName -Name $_.LabPlanName
        
        if (!(Get-Member -InputObject $_ -Name 'TemplateVmState')) {
            Write-Warning "Missing lab's template VM value - defaulting to 'Enabled'.  Column name: TemplateVM."
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "TemplateVmState" -Value 'Enabled'
        }
        if (Get-Member -InputObject $_ -Name 'TemplateVmState') {
            if ($_.TemplateVmState -ieq "Enabled" -or $_.TemplateVmState -ieq "True") {
                $_.TemplateVmState = "TemplateVM"
            } 
            else {
                $_.TemplateVmState = "Image"
            }
        }

        if (!(Get-Member -InputObject $_ -Name 'Location')) {
            Write-Warning "Missing lab's Location value that designates the region the lab will be created.  Defaulting to lab plan's Location.  Column name: Location."
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "Location" -Value $labPlan.Location
        }
        else {
            if (($labPlan.Location -ne $_.Location) -and ($_.TemplateVmState -ieq "Enabled")) {
                Write-Warning "If you need to export images from the lab's template VM, the lab's location must match the lab plan's location due to product limitation.  Lab plan: $($_.LabPlanName) Lab plan location: $($labPlan.Location) Lab location: $($_.Location)."
            }
            
            if ($labPlan.AllowedRegion.ToLower() -notcontains $_.Location.ToLower()) {
                Write-Error "Lab's location must be one of the enabled regions for the lab plan.  Lab plan: $($_.LabPlanName) Allowed regions: $($labPlan.AllowedRegion) Lab location: $($_.Location)."
            }
        }
        
        # Validate that the name is good, before we start creating labs
        if (-not ($_.LabName -match "^[a-zA-Z0-9_, '`"!|-]*$")) {
            Write-Error "Lab Name '$($_.LabName)' can't contain special characters..."
        }

        if ((Get-Member -InputObject $_ -Name 'AadGroupId') -and ($_.AadGroupId)) {
            # Validate that the aadGroupId (if it exists) isn't a null guid since that's not valid (it's in the default csv this way)
            if ($_.AadGroupId -ieq "00000000-0000-0000-0000-000000000000") {
                Write-Error "AadGroupId cannot be all 0's for Lab '$($_.LabName)', please enter a valid AadGroupId"
            }

            # We have to ensure 
            if ((Get-Member -InputObject $_ -Name 'MaxUsers') -and ($_.MaxUsers)) {
                Write-Warning "Max users and AadGroupId cannot be specified together, MaxUsers will be ignored for lab '$($_.LabName)'"
                $_.MaxUsers = ""
            }
        }

        # Image and lab connection set up
        if ($_.ImageName) {
            Set-LabImageProperties -Lab $_ -LabPlan $labPlan
            if ((Get-Member -InputObject $_ -Name 'ImageOSType') -and $_.ImageOSType) {
                # The RDP/SSH connection properties are based on the image's OS type
                Set-LabConnectionProperties -Lab $_
            }
            else {
                Write-Error "Unable to determine if lab's image is Linux or Windows to set RDP/SSH connection properties. Lab: $($_.LabName)."
            }
        }
        else {
            Write-Error "ImageName must provide valid lab image name."
        }

        # Checking to ensure the user has changed the example username/password in CSV files for the admin and non-admin credentials.
        # Note that the non-admin credentials are optional in the csv file.
        if ($_.UserName -and ($_.UserName -like "*test*")) {
            Write-Warning "Lab $($_.LabName) is using 'test' in the UserName.  Please ensure you're providing the 
            a valid username for the lab's admin user."
        }
        if ($_.Password -and ($_.Password -like "*test*")) {
            Write-Warning "Lab $($_.LabName) is using 'test' in the Password.  Please ensure you're providing a strong password for the lab's admin user for security reasons."
        }

        if ((Get-Member -InputObject $_ -Name 'NonAdminUserName') -and ($_.NonAdminUserName)) {
            if ($_.NonAdminUserName -and ($_.NonAdminUserName -like "*test*")) {
                Write-Warning "Lab $($_.LabName) is using 'test' in the NonAdminUserName.  Please ensure you're providing a valid username for the lab's non-admin user."
            }

            if ($_.UserName -ieq $_.NonAdminUserName) {
                # If not unique, causes a Bad Request when creating the lab
                Write-Error "Lab $($_.LabName) has the same UserName and NonAdminUserName.  Please update one of them so that they are unique."
            }
        }
        if ((Get-Member -InputObject $_ -Name 'NonAdminPassword') -and ($_.NonAdminPassword)) {
            if ($_.NonAdminPassword -and ($_.NonAdminPassword -like "*test*")) {
                Write-Warning "Lab $($_.LabName) is using 'test' in the NonAdminPassword.  Please ensure you're providing a strong password for the lab's non-admin user for security reasons."
            }
        }       

        if ((Get-Member -InputObject $_ -Name 'Size') -and ($_.Size)) {
            $_.Size = Validate-SkuName -Sku $_.Size -labLocation $_.Location
        }
        else {
            Write-Error "Size is a required field, cannot continue without it"
        }

        if ((Get-Member -InputObject $_ -Name 'Emails') -and ($_.Emails)) {
            $_.Emails = ($_.Emails.Split(';')).Trim()
        }
        elseif (!(Get-Member -InputObject $_ -Name 'Emails')) {
            #Assign to empty array since New-AzLab expects this property to exist, but this property should be optional in the csv
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "Emails" -Value @() 
        }

        if ((Get-Member -InputObject $_ -Name 'LabOwnerEmails') -and ($_.LabOwnerEmails)) {
            $_.LabOwnerEmails = ($_.LabOwnerEmails.Split(';')).Trim()
        }
        elseif (!(Get-Member -InputObject $_ -Name 'LabOwnerEmails')) {
            #Assign to empty array since New-AzLab expects this property to exist, but this property should be optional in the csv
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "LabOwnerEmails" -Value @() 
        }

        if (!(Get-Member -InputObject $_ -Name 'SharedPassword')) {
            Write-Warning "Missing lab's SharedPassword value - defaulting to 'Enabled'.  Column name: SharedPassword."
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "SharedPassword" -Value 'Enabled'
        }
        else {
            if ($_.SharedPassword -ieq "Enabled" -or $_.SharedPassword -ieq "True") {
                $_.SharedPassword = "Enabled"
            } 
            else {
                $_.SharedPassword = "Disabled"
            }
        }

        if (!(Get-Member -InputObject $_ -Name 'UsageMode')) {
            #  Default to restricted since this is the most secure option
            Write-Warning "Missing lab's UsageMode value - defaulting to 'Restricted'.  Column name: UsageMode."
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "UsageMode" -Value 'Enabled'
        }
        else {
            if ($_.UsageMode -ieq "Restricted") {
                $_.UsageMode = "Enabled"
            } 
            else {
                $_.UsageMode = "Disabled"
            }
        }    

        if (!(Get-Member -InputObject $_ -Name 'GpuDriverEnabled')) {
            # Default to disabled since this column will typically be ommitted when non-GPU labs are being created
            Write-Verbose "Missing lab's GpuDriverEnabled value - defaulting to 'Disabled'.  Column name: GpuDriverEnabled."
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "GpuDriverEnabled" -Value 'Disabled'
        }
        if (Get-Member -InputObject $_ -Name 'GpuDriverEnabled') {
            if ($_.GpuDriverEnabled -ieq "Enabled" -or $_.GpuDriverEnabled -ieq "True") {
                $_.GpuDriverEnabled = "Enabled"
            } 
            else {
                $_.GpuDriverEnabled = "Disabled"
            }
        }
      
        if ((Get-Member -InputObject $_ -Name 'Schedules') -and ($_.Schedules)) {
            Write-Verbose "Setting schedules for $($_.LabName)"
            $_.Schedules = Import-Schedules -schedules $_.Schedules
        }
        elseif (!(Get-Member -InputObject $_ -Name 'Schedules')) {
            #Assign to empty array since New-AzLab expects this property to exist, but this property should be optional in the csv
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "Schedules" -Value @() 
        }
    }

    Write-Verbose ($labs | ConvertTo-Json -Depth 40 | Out-String)

    return ,$labs # PS1 Magick here, the comma is actually needed. Don't ask why.
    # Ok, here is why, PS1 puts each object in the collection on the pipeline one by one
    # unless you say explicitely that you want to pass it as a single object
}

function Set-LabImageProperties {
    param(
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]
        $Lab,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]
        $LabPlan
    )
    
    Write-Verbose "Validating provided image. Image name: $($Lab.ImageName)."
    if ((Get-Member -InputObject $Lab -Name 'SharedGalleryId') -and ($Lab.SharedGalleryId)) {
        Write-Verbose "Validating lab's shared image properties. SharedGalleryId: $($Lab.SharedGalleryId)."
   
        # Ensure the provided SharedGalleryId is valid by checking that it matches the lab plan's Shared Image/Compute Gallery
        if (!$Lab.SharedGalleryId.ToLower().StartsWith($LabPlan.SharedGalleryId.ToLower())) {
            Write-Error "An unexpected Shared Image/Compute Gallery is attached to the lab plan.  Lab plan: $($Lab.LabPlanName)) Expected gallery: $($Lab.SharedGalleryId) Actual gallery: $($LabPlan.SharedGalleryId))"
        }
    }

    # Must filter on the server because this returns all images available on a lab plan (includes both marketplace and shared image/compute gallery images)
    $targetImageName = $Lab.ImageName.ToLower()
    $filterQuery = "indexof(tolower(properties/displayName),'$($targetImageName)') gt -1 and properties/enabledState eq 'Enabled'" 
    $imageResult = Get-AzLabServicesPlanImage -LabPlanName $Lab.LabPlanName -ResourceGroupName $Lab.ResourceGroupName -Filter $filterQuery

    if (!$imageResult) {
        Write-Error "No images found.  Ensure that the correct image name was provided and that the image is enabled on the lab plan. Image name: $($Lab.ImageName), Lab plan: $($Lab.LabPlanName), Lab: $($Lab.LabName)."
    }
    elseif (@($imageResult).Count -ne 1) { 
        Write-Error "Must match exactly one image with the provided image name. Image name: $($Lab.ImageName), Lab: $($Lab.LabName), Actual match count: $($imageResult.Count)."
    }
    else {
        $foundImage = @($imageResult)[0];

        $imageInformation = @{}
        if ($foundImage.SharedGalleryId -and $foundImage.AvailableRegion) {
                    
            # Since this is a gallery image, check that it's been replicated to the lab's region
            if (!$foundImage.AvailableRegion.ToLower().Contains($_.Location.ToLower())) {
                Write-Error "Image must be replicated to the lab's region. Region: $($Lab.Location)"
            }
    
            $imageInformation.Add("ImageReferenceId",$foundImage.SharedGalleryId)
         }
         else {
            $imageInformation.Add("ImageReferenceOffer",$foundImage.Offer)
            $imageInformation.Add("ImageReferencePublisher",$foundImage.Publisher)
            $imageInformation.Add("ImageReferenceSku",$foundImage.Sku)
            $imageInformation.Add("ImageReferenceVersion",$foundImage.Version)
         }
    
         Add-Member -InputObject $Lab -MemberType NoteProperty -Name "ImageInformation" -Value $imageInformation
         Add-Member -InputObject $Lab -MemberType NoteProperty -Name "ImageOSType" -Value $foundImage.OSType
         Write-Verbose "Finished setting lab's image properties." 
    }
}

function Set-LabConnectionProperties {
    param(
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]
        $Lab
    )

    Write-Verbose "Validating lab's connection properties. Image OS type: $($Lab.ImageOSType)."

    $linuxRdp = $false

    if (Get-Member -InputObject $Lab -Name 'LinuxRdp') {
        if ($Lab.LinuxRdp) {
            if ($Lab.LinuxRdp -ieq "Enabled" -or $Lab.LinuxRdp -ieq "True") {
                $linuxRdp  = $true
            } 

            if ($linuxRdp -and $Lab.ImageOSType -ne "Linux") {
                Write-Error "Linux Rdp can only be enabled for a Linux image.  LinuxRdp: $($linuxRdp), ImageName: $($Lab.ImageName)"
            }
        }
    }
     
    $connectionProfile = @{}
    if ($Lab.ImageOSType -eq "Windows") {
        $connectionProfile.Add("ConnectionProfileClientRdpAccess", "Public")
        $connectionProfile.Add("ConnectionProfileClientSshAccess", "None")
        Write-Verbose "Enabling lab's Windows RDP connection settings."        
     } 
     elseif ($linuxRdp) {
        $connectionProfile.Add("ConnectionProfileClientRdpAccess", "Public")
        $connectionProfile.Add("ConnectionProfileClientSshAccess", "Public")
        Write-Verbose "Enabling lab's Linux RDP/SSH connection settings."
     } 
     else {
        $connectionProfile.Add("ConnectionProfileClientRdpAccess", "None")
        $connectionProfile.Add("ConnectionProfileClientSshAccess", "Public")
        Write-Verbose "Enabling lab's Linux SSH connection settings."
     }
     
     Add-Member -InputObject $Lab -MemberType NoteProperty -Name "ConnectionProfile" -Value $connectionProfile
     Write-Verbose "Finished setting lab's connection properties." 
}

function Export-LabsCsv {
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]
        $labs,

        [parameter(Mandatory = $true)]
        [string]
        $CsvConfigFile,

        [parameter(Mandatory = $false)]
        [switch] $Force
    )

    begin
    {
        $outArray = @()
    }

    process
    {
        # Iterate over the labs and pull out the inner properties (orig object) and add in result fields
        $labs | ForEach-Object {
            $obj = $_

            # If we don't have the underlying properties, need to bail out
            if (-not (Get-Member -InputObject $_ -Name OriginalProperties)) {
                Write-Error "Cannot write out labs CSV, input labs object doesn't contain original properties"
            }

            $outObj = $_.OriginalProperties

            # We need to copy any 'result' fields over to the original object we're writing out
            Get-Member -InputObject $obj -Name "*Result" | ForEach-Object {
                if (Get-Member -InputObject $outObj -Name $_.Name) {
                    $outObj.$($_.Name) = $obj.$($_.Name)
                }
                else {
                    Add-Member -InputObject $outObj -MemberType NoteProperty -Name $_.Name $obj.$($_.Name)
                }
            }

            # Add the object to the cumulative array
            $outArray += $outObj
        }
    }

    end
    {
        if ($Force.IsPresent) {
            $outArray | Export-Csv -Path $CsvConfigFile -NoTypeInformation -Force
        }
        else {
            $outArray | Export-Csv -Path $CsvConfigFile -NoTypeInformation -NoClobber
        }
    }
}

function New-AzLabPlansBulk {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab plan to be created", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labPlans,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab account creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $LabPlans is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labPlans
    }
    end {
        $init = {            
        }

        # No need to parallelize this one as super fast
        function New-ResourceGroups {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject
            )

            $Rgs = $ConfigObject | Select-Object -Property ResourceGroupName, Location, Tags -Unique
            Write-Verbose "Looking for the following resource groups:"
            $Rgs | Format-Table | Out-String | Write-Verbose
            
            $Rgs | ForEach-Object {
                if (-not (Get-AzResourceGroup -ResourceGroupName $_.ResourceGroupName -EA SilentlyContinue)) {
                    if ((Get-Member -InputObject $_ -Name 'Tags') -and ($_.Tags)) {
                        $taghash = ConvertFrom-StringData -StringData ($_.Tags.Replace(";","`r`n"))
                    }
                    else {
                        $taghash = $null
                    }
                    New-AzResourceGroup -ResourceGroupName $_.ResourceGroupName -Location $_.Location -Tags $taghash | Out-null
                    Write-Host "$($_.ResourceGroupName) resource group didn't exist. Created it." -ForegroundColor Green
                }
            }
        }
        
        function New-AzPlan-Jobs {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject
            )

            $block = {
                param($path)

                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'
                
                Import-module -Name Az.Labservices
                
                $input.movenext() | Out-Null
            
                $obj = $input.current[0]

                Write-Verbose "object inside the new-azplan-jobs block $obj"
                $StartTime = Get-Date

                Write-Host "Creating Lab Plan: $($obj.LabPlanName)"
                
                if ((Get-Member -InputObject $obj -Name 'Tags') -and ($obj.Tags)) {
                    $taghash = ConvertFrom-StringData -StringData ($obj.Tags.Replace(";","`r`n"))
                }
                else {
                    $taghash = $null
                }

                if ($obj.SharedGalleryId){
                    
                    $labPlan = New-AzLabServicesLabPlan -ResourceGroupName $obj.ResourceGroupName -Name $obj.LabPlanName -SharedGalleryId $obj.SharedGalleryId -Location $obj.Location -AllowedRegion @($obj.Location) -Tag $taghash

                    # This will enable the SIG images explicitly listed in the csv.  
                    # For SIG images that are *not* listed in the csv, this will automatically disable them.
                    Write-Host "Enabling images for lab plan: $($labPlan.Name)"
                    if ($obj.EnableSharedGalleryImages)
                    {
                        $imageNamesToEnable = $obj.EnableSharedGalleryImages.Split(',')

                        Write-Verbose "Images to enable: $imageNamesToEnable"
                        $images = Get-AzLabServicesPlanImage -ResourceGroupName $obj.ResourceGroupName -LabPlanName $obj.LabPlanName | Where-Object -Property SharedGalleryId -Match -Value "$($obj.SharedGalleryId)"
                            # Doesnt work-Filter "Properties/SharedGalleryId eq '$($obj.SharedGalleryId)'"

                        foreach ($image in $images) {
                            $enableImage = $imageNamesToEnable -contains ($image.Name) # Note: -contains is case insensitive
                            
                            if ($enableImage -eq $true){
                                Write-Verbose "Enabling image: $($image.Name)"
                                $image = Update-AzLabServicesPlanImage -LabPlanName $obj.LabPlanName -ResourceGroupName $obj.ResourceGroupName -Name $image.Name -EnabledState Enabled
                            }
                            else {
                                Write-Verbose "Disabling image: $($image.Name)"
                                $image = Update-AzLabServicesPlanImage -LabPlanName $obj.LabPlanName -ResourceGroupName $obj.ResourceGroupName -Name $image.Name -EnabledState Disabled
                            }
                        }
                    }

                    Write-Verbose "Completed creation of $($obj.SharedGalleryId), total duration $(((Get-Date) - $StartTime).TotalSeconds) seconds"
                } else {
                    $labPlan = New-AzLabServicesLabPlan -ResourceGroupName $obj.ResourceGroupName -Name $obj.LabPlanName -Location $obj.Location -AllowedRegion @($obj.Location) -Tag $taghash
                }

                Write-Host "Completed creation of $($obj.LabPlanName), total duration $([math]::Round(((Get-Date) - $StartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green
            }

            Write-Host "Starting creation of all lab plans in parallel. Can take a while."
            $plans = $ConfigObject | Select-Object -Property ResourceGroupName, LabPlanName, Location, SharedGalleryId, EnableSharedGalleryImages, Tags -Unique

            Write-Verbose "Operating on the following Lab Accounts:"
            Write-Verbose ($plans | Format-Table | Out-String)

            $jobs = @()

            # Stagger starting threads to avoid Azure KeyStore locked error that an occur when too many threads are started in parallel
            foreach ($config in $ConfigObject) {
                Write-Verbose "From config: $config"
                $jobs += Start-ThreadJob  -InitializationScript $init -ScriptBlock $block -ArgumentList $PSScriptRoot -InputObject $config -Name ("$($config.ResourceGroupName)+$($config.LabPlanName)") -ThrottleLimit $ThrottleLimit
                Start-Sleep -Seconds 1
            }
    
            return JobManager -currentJobs $jobs -ResultColumnName "LabPlanResult" -ConfigObject $ConfigObject
        }

        # Needs to create resources in this order, aka parallelize in these three groups, otherwise we get contentions:
        # i.e. different jobs trying to create the same common resource (RG or lab account)
        New-ResourceGroups  -ConfigObject $aggregateLabs
        # New-AzAccount-Jobs returns the config object with an additional column, we need to leave it on the pipeline
        New-AzPlan-Jobs   -ConfigObject $aggregateLabs
    }
}

function New-AzLabsBulk {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab to be created", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $labs is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs
    }
    end {
        $init = {
            
        }
        function New-AzLab-Jobs {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject
            )

            $block = {
                param($path)

                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'

                Import-Module -Name Az.LabServices
                $input.movenext() | Out-Null
            
                $obj = $input.current[0]

                Write-Verbose "object inside the new-azlab-jobs block $obj"

                $StartTime = Get-Date
                Write-Host "Creating Lab : $($obj.LabName)"
                
                $currentLab = $null
                $plan = $null
                try {
                    $plan = Get-AzLabServicesLabPlan -ResourceGroupName $obj.ResourceGroupName -Name $obj.LabPlanName
                } catch {
                    Write-Error "Unable to find lab plan $($obj.LabPlanName)."
                }

                $lab = $null
                try {
                    $lab = $plan | Get-AzLabServicesLab -Name $obj.LabName
                }
                catch {
                    Write-Host "Unable to find lab $($obj.LabName), creating."
                }

                if ($lab) {
                    Write-Host "Lab already exists."
                    $currentLab = $plan | Get-AzLabServicesLab -Name $obj.LabName
                }
                else {

                    # Get value for optional idle grace period parameter
                    $idleGracePeriodParameters = @{}
                    if ($obj.idleGracePeriod -ge 1) {
                        $idleGracePeriodParameters.Add("AutoShutdownProfileShutdownOnIdle","UserAbsence")
                        $idleGracePeriodParameters.Add("AutoShutdownProfileIdleDelay",$(New-TimeSpan -Minutes $obj.idleGracePeriod).ToString())                        
                    } else {
                        $idleGracePeriodParameters.Add("AutoShutdownProfileShutdownOnIdle","None")
                    }

                    # Get value for optional disconnect on idle parameter
                    $enableDisconnectOnIdleParameters = @{}
                    if ($obj.idleOsGracePeriod -ge 1) {
                        $enableDisconnectOnIdleParameters.Add("AutoShutdownProfileShutdownOnDisconnect","Enabled")
                        $enableDisconnectOnIdleParameters.Add("AutoShutdownProfileDisconnectDelay",$(New-TimeSpan -Minutes $obj.idleOsGracePeriod).ToString())
                    } else {
                        $enableDisconnectOnIdleParameters.Add("AutoShutdownProfileShutdownOnDisconnect","Disabled")
                    }

                    # Get value for optional grace period when not connected parameter
                    $idleNoConnectGracePeriodParameters = @{}
                    if ($obj.idleNoConnectGracePeriod -ge 1) {
                        $idleNoConnectGracePeriodParameters.Add("AutoShutdownProfileShutdownWhenNotConnected","Enabled")
                        $idleNoConnectGracePeriodParameters.Add("AutoShutdownProfileNoConnectDelay", $(New-TimeSpan -Minutes $obj.idleNoConnectGracePeriod).ToString())
                    } else {
                        $idleNoConnectGracePeriodParameters.Add("AutoShutdownProfileShutdownWhenNotConnected","Disabled")
                    }

                    # If the lab plan has a subnet, we should use it in the create lab request
                    $subnetParameters = @{}
                    if ($plan -and $plan.DefaultNetworkProfileSubnetId) {
                        $subnetParameters = @{
                            NetworkProfileSubnetId = $plan.DefaultNetworkProfileSubnetId
                        }
                    }
                   
                    # Get value for optional non-admin credentials parameter
                    $nonAdminCreds = @{}
                    if ((Get-Member -InputObject $obj -Name 'NonAdminUsername') -and ($obj.NonAdminUsername)) {
                        $nonAdminCreds = @{
                            NonAdminUserUsername = $obj.NonAdminUsername
                            NonAdminUserPassword  = $(ConvertTo-SecureString $obj.NonAdminPassword -AsPlainText -Force);
                        }
                    }
         
                    # Get value for optional Tags parameter
                    $customTags = @{}
                    if ((Get-Member -InputObject $obj -Name 'Tags') -and ($obj.Tags)) {
                        $customTags = @{
                            Tag = ConvertFrom-StringData -StringData ($obj.Tags.Replace(";","`r`n"))
                        }
                    }

                    # Set required parameters for creating a new lab
                    $requiredNewLabParameters = @{
                        Name = $obj.LabName;
                        ResourceGroupName = $obj.ResourceGroupName;
                        Location = $obj.Location;
                        Title = $obj.Title;
                        Description = $obj.LabName;
                        AdminUserPassword = $(ConvertTo-SecureString $obj.Password -AsPlainText -Force);
                        AdminUserUsername = $obj.UserName;
                        AdditionalCapabilityInstallGpuDriver = $obj.GpuDriverEnabled;
                        LabPlanId = $plan.Id;
                        SecurityProfileOpenAccess = $obj.UsageMode;
                        SkuCapacity = $obj.MaxUsers;
                        SkuName = $obj.Size;
                        VirtualMachineProfileCreateOption = $obj.TemplateVmState;
                        VirtualMachineProfileUsageQuota = $(New-TimeSpan -Hours $obj.UsageQuota).ToString();
                        VirtualMachineProfileUseSharedPassword = $obj.SharedPassword;
                        ConnectionProfileWebRdpAccess = "None";
                        ConnectionProfileWebSshAccess = "None";
                    }

                    $requiredNewLabParameters += $obj.ConnectionProfile;
                    $requiredNewLabParameters += $obj.ImageInformation;

                    # Set optional parameters for creating a new lab
                    $optionalNewLabParameters = $nonAdminCreds + `
                                         $idleGracePeriodParameters + `
                                         $enableDisconnectOnIdleParameters + `
                                         $idleNoConnectGracePeriodParameters + `
                                         $customTags + `
                                         $subnetParameters

                    $fullParameterList = $requiredNewLabParameters + $optionalNewLabParameters

                    Write-Host "Starting lab creation $($obj.LabName)"

                    try {
                        $currentLab = New-AzLabServicesLab @fullParameterList
                    }
                    catch {
                        Write-Host "In Catch: $_"
                        Start-Sleep -Seconds 30
                        $currentLab = New-AzLabServicesLab @fullParameterList
                    }
                    Write-Host "Lab $($obj.LabName) provisioning state $($currentLab.ProvisioningState)"
                    Write-Host "Completed lab creation step in $([math]::Round(((Get-Date) - $StartTime).TotalMinutes, 1)) minutes"

                    # In the case of AAD Group, we have to force sync users to update the MaxUsers property
                    if ((Get-Member -InputObject $obj -Name 'AadGroupId') -and ($obj.AadGroupId)) {
                        Write-Host "syncing users from AAD ..."
                        Sync-AzLabServicesLabUser -LabName $lab.Name -ResourceGroupName $obj.ResourceGroupName | Out-Null
                    }
                    
                    # If we have any lab owner emails, we need to assign the RBAC permission
                    if ($obj.LabOwnerEmails) {
                        Write-Host "Adding Lab Owners: $($obj.LabOwnerEmails) ."
                        $obj.LabOwnerEmails | ForEach-Object {
                            # Need to ensure we didn't get an empty string, in case there's an extra delimiter
                            if ($_) {
                                # Check if Lab Owner role already exists (the role assignment is added by default by the person who runs the script), if not create it
                                $userPrincipalName = (Get-AzAdUser -Mail $_).UserPrincipalName
                                if (-not (Get-AzRoleAssignment -SignInName $userPrincipalName -Scope $currentLab.id -RoleDefinitionName Owner)) {
                                    New-AzRoleAssignment -SignInName $userPrincipalName -Scope $currentLab.id -RoleDefinitionName Owner | Out-Null
                                }
                                # Check if the lab account reader role already exists, if not create it
                                if (-not (Get-AzRoleAssignment -SignInName $userPrincipalName -ResourceGroupName $obj.ResourceGroupName -ResourceName $obj.LabPlanName -ResourceType "Microsoft.LabServices/LabPlans" -RoleDefinitionName Reader)) {
                                    New-AzRoleAssignment -SignInName $userPrincipalName -ResourceGroupName $obj.ResourceGroupName -ResourceName $obj.LabPlanName -ResourceType "Microsoft.LabServices/LabPlans" -RoleDefinitionName Reader | Out-Null 
                                }
                            }
                        }
                        Write-Host "Added Lab Owners: $($obj.LabOwnerEmails)." -ForegroundColor Green
                    }
                }
                
                #Section to send out invitation emails
                if ($obj.Emails) {
                    Write-Host "Adding users for $($obj.LabName) for users $($obj.Emails)."
                    foreach ($email in $obj.Emails) {  
                        $user = $null
                        try {
                            $user = Get-AzLabServicesUser -LabName $currentLab.Name -ResourceGroupName $obj.ResourceGroupName | Where-Object {$_.email -ieq $email}
                            if (!$user) {
                                $tempGuid = New-Guid            
                                $user = New-AzLabServicesUser -Name $tempGuid.Guid.ToString() -LabName $currentLab.Name -ResourceGroupName $obj.ResourceGroupName -Email $email    
                            }
                        } catch {
                            $tempGuid = New-Guid            
                            $user = New-AzLabServicesUser -Name $tempGuid.Guid.ToString() -LabName $currentLab.Name -ResourceGroupName $obj.ResourceGroupName -Email $email    
                        }

                        if ($obj.Invitation) {
                            Write-Host "Sending Invitation emails for $($obj.LabName)."
                            Send-AzLabServicesUserInvite -ResourceGroupName $obj.ResourceGroupName -LabName $obj.LabName -UserName $user.name -Text $obj.Invitation | Out-Null
                        }
                    }
                }

                if ($obj.Schedules) {
                    Write-Host "Adding Schedules for $($obj.LabName)."

                    foreach($schedule in $obj.Schedules) {
                        
                        $sdate = [datetime]::Parse($schedule.FromDate)
                        $stime = [datetime]::Parse($schedule.StartTime.Replace('"',''))
                        $startd = [datetime]::New($sdate.Year, $sdate.Month, $sdate.Day, $stime.Hour, $stime.Minute, 0)
                        $fullStart = $startd.ToString('u')

                        $etime = [datetime]::Parse($schedule.EndTime.Replace('"',''))
                        $endd = [datetime]::New($sdate.Year, $sdate.Month, $sdate.Day, $etime.Hour, $etime.Minute, 0)
                        $fullEnd = $endd.ToString('u')

                        $edate = [datetime]::Parse($schedule.ToDate.Replace('"',''))
                        $duntil = [datetime]::New($edate.Year, $edate.Month, $edate.Day, 23, 59, 59)
                        $fullUntil = $duntil.ToString('u')

                        [Microsoft.Azure.PowerShell.Cmdlets.LabServices.Support.WeekDay[]]$weekdays = $null
                        foreach ($day in ($schedule.WeekDays -Split ";")) {
                            $weekdays += [Microsoft.Azure.PowerShell.Cmdlets.LabServices.Support.WeekDay]$day.Trim("""").ToString()
                        }
                        # Check if schedules exist.
                        $zschedules = $currentLab | Get-AzLabServicesSchedule

                        if (!($zschedules | Where-Object {(($startd -ge $_.StartAt) -and ($startd -le $_.StopAt)) -or (($endd -ge $_.StartAt) -and ($endd -le $_.StopAt))})) {
                        #if (!($currentLab | Get-AzLabServicesSchedule)) {
                            if ($schedule.Frequency -eq "Once") {
                                New-AzLabServicesSchedule -Lab $currentLab -Name $('Default_' + (Get-Random -Minimum 10000 -Maximum 99999)) -Note $($schedule.Notes) `
                                    -StartAt $fullStart `
                                    -StopAt $fullEnd `
                                    -TimeZoneId $($schedule.TimeZoneId) | Out-Null
                            } else {
                                New-AzLabServicesSchedule -Lab $currentLab -Name $('Default_' + (Get-Random -Minimum 10000 -Maximum 99999)) -Note $($schedule.Notes) `
                                    -RecurrencePatternExpirationDate $fullUntil `
                                    -RecurrencePatternFrequency $($schedule.Frequency) `
                                    -RecurrencePatternInterval 1 `
                                    -RecurrencePatternWeekDay $weekdays `
                                    -StartAt $fullStart `
                                    -StopAt $fullEnd `
                                    -TimeZoneId $($schedule.TimeZoneId) | Out-Null
                            }
                        } else {
                            Write-Host "Duplicate schedules not added on lab $($currentLab.Name)"
                        }
                    }

                    Write-Host "Added all schedules."
                }

                Write-Host "Completed all tasks for $($obj.LabName), total duration $([math]::Round(((Get-Date) - $StartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green
            }

            Write-Host "Starting creation of all labs in parallel. Can take a while."
            $jobs = @()

            # Stagger starting threads to avoid Azure KeyStore locked error that an occur when too many threads are started in parallel
            foreach ($config in $ConfigObject) {
                Write-Verbose "From config: $config"
                $jobs += Start-ThreadJob  -InitializationScript $init -ScriptBlock $block -ArgumentList $PSScriptRoot -InputObject $config -Name  ("$($config.ResourceGroupName)+$($config.LabPlanName)+$($config.LabName)") -ThrottleLimit $ThrottleLimit
                Start-Sleep -Seconds 1
            }

            Write-Verbose "Job count: $($jobs.Count)"
            return JobManager -currentJobs $jobs -ResultColumnName "LabResult" -ConfigObject $ConfigObject
        }

        New-AzLab-Jobs -ConfigObject $aggregateLabs 
    }
}

function Set-AzRoleToLabPlansBulk {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab to be created", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $RoleDefinitionName
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $labs is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs
    }
    end {
        $init = {
            
        }
        function Set-AzRoleToLabPlan-Jobs {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject,

                [parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]
                $RoleDefinitionName
            )

            $block = {
                param($path, $RoleDefinitionName)

                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'

                Import-Module -Name Az.LabServices
                # Really?? It got to be the lines below? Doing a ForEach doesn't work ...
                $input.movenext() | Out-Null
            
                $obj = $input.current[0]

                Write-Host "Started operating on lab account:  '$($obj.LabPlanName)' in resource group '$($obj.ResourceGroupName)'"
                Write-Verbose "object inside the assign-azRoleToLabPlan-jobs block $obj"

                if((Get-Member -InputObject $obj -Name 'LabPlanCustomRoleEmails') -and ($obj.LabPlanCustomRoleEmails)) {
                            
                    $emails = @($obj.LabPlanCustomRoleEmails -split ';')
                    $emails = @($emails | Where-Object {-not [string]::IsNullOrWhiteSpace($emails) })
                    if ($emails.Length -eq 0){
                        Write-Verbose "No emails specified for role assignment."
                    }
                    else {

                        try {
                            $plan = Get-AzLabServicesPlan -ResourceGroupName $obj.ResourceGroupName -LabPlanName $obj.LabPlanName
                        }
                        catch {
                            Write-Error "Unable to find lab plan '$($obj.LabPlanName)'"
                        }
                        # if (-not $plan -or @($plan).Count -ne 1) {
                        #     Write-Error "Unable to find lab plan '$($obj.LabPlanName)'"
                        # } 

                        foreach ($email in $emails) {
                            #Get AD object id for user.  Try both user principal name and mail emails
                            $userAdObject = $null
                            $userAdObject = Get-AzADUser -UserPrincipalName $email.ToString().Trim() -ErrorAction SilentlyContinue
                            if (-not $userAdObject){
                                $userAdObject = Get-AzADUser -Mail $email.ToString().Trim() -ErrorAction SilentlyContinue
                            }
                            if (-not $userAdObject){
                                Write-Error "Couldn't find user '$email' in Azure AD."
                            }

                            #Check if role assignment already exists.
                            if (Get-AzRoleAssignment -ObjectId $userAdObject.Id -RoleDefinitionName $RoleDefinitionName -Scope $la.id -ErrorAction SilentlyContinue) {
                                Write-Host "Role Assignment $RoleDefinitionName for $email for lab account $($obj.LabPlanName) already exists."
                            }
                            else {
                                Write-Host "Creating new role ssignment $RoleDefinitionName for $email for lab account $($obj.LabPlanName)."
                                $result = New-AzRoleAssignment -ObjectId $userAdObject.Id -RoleDefinitionName $RoleDefinitionName -Scope $la.id
                            }
                        }
                    }
                }
                else {
                    Write-Host "No emails specified for role assignment" -ForegroundColor Yellow         
                }    
             }

            Write-Host "Starting role assignment for lab accounts in parallel. Can take a while."

            # NOTE: the Get-AzureAdUser commandlet will throw an error if the user isn't logged in
            if (-not (Get-AzAdUser -First 1)) {
                Write-Error "Unable to access Azure AD users using Get-AzAdUser commandlet, you don't have sufficient permission to the AD Tenant to use this commandlet"
            }

            $jobs = @()

            $ConfigObject | ForEach-Object {
                Write-Verbose "From config: $_"
                $jobs += Start-ThreadJob  -InitializationScript $init -ScriptBlock $block -ArgumentList $PSScriptRoot, $RoleDefinitionName -InputObject $_ -Name  ("$($_.ResourceGroupName)+$($_.LabPlanName)") -ThrottleLimit $ThrottleLimit
            }

            while (($jobs | Measure-Object).Count -gt 0) {
                # If we have more jobs, wait for 30 sec before checking job status again
                Start-Sleep -Seconds 30

                $completedJobs = $jobs | Where-Object {($_.State -ieq "Completed") -or ($_.State -ieq "Failed")}
                if (($completedJobs | Measure-Object).Count -gt 0) {
                    # Write output for completed jobs, but one by one so output doesn't bleed 
                    # together, also use "Continue" so we write the error but don't end the outer script
                    $completedJobs | ForEach-Object {
                        $_ | Receive-Job -ErrorAction Continue
                    }
                    # Trim off the completed jobs from our list of jobs
                    $jobs = $jobs | Where-Object {$_.Id -notin $completedJobs.Id}
                    # Remove the completed jobs from memory
                    $completedJobs | Remove-Job
                }
            }
        }

        Set-AzRoleToLabPlan-Jobs  -ConfigObject $aggregateLabs -RoleDefinitionName $RoleDefinitionName
    }
}

function Remove-AzLabsBulk {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab to be removede", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab account creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $LabPlans is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs
    }
    end {
        $init = {            
        }

        # No need to parallelize this one as super fast
         function Remove-AzLabs-Jobs {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject
            )

            $block = {
                param($path)

                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'

                Import-Module -Name Az.LabServices
                # Really?? It got to be the lines below? Doing a ForEach doesn't work ...
                $input.movenext() | Out-Null
            
                $obj = $input.current[0]

                Write-Verbose "object inside the remove-azlabs-jobs block $obj"
                $StartTime = Get-Date

                try {
                    Write-Host "Removing Lab: $($obj.LabName)"
                    $plan = Get-AzLabServicesLabPlan -ResourceGroupName $obj.ResourceGroupName -Name $obj.LabPlanName
                }
                catch {
                    Write-Error "Unable to find lab plan $($obj.LabPlanName)."
                }

                try {
                    $lab = $plan | Get-AzLabServicesLab -Name $obj.LabName
                    $output = Remove-AzLabServicesLab -Lab $lab
                    Write-Host "Removal output: $output"
                    Write-Host "Completed removal of $($obj.LabName), total duration $([math]::Round(((Get-Date) - $StartTime).TotalMinutes, 1)) minutes"
    
                }
                catch {
                    Write-Error "Unable to find or remove lab $($obj.LabName)."
                }
                
            }

            Write-Host "Starting removal of all labs in parallel. Can take a while."
            $labs = $ConfigObject | Select-Object -Property ResourceGroupName, LabPlanName, LabName -Unique
            
            Write-Verbose "Operating on the following Lab Plans:"
            Write-Verbose ($labs | Format-Table | Out-String)

            $jobs = @()

            # Stagger starting threads to avoid Azure KeyStore locked error that an occur when too many threads are started in parallel
            foreach ($config in $ConfigObject) {
                Write-Verbose "From config: $config"
                $jobs += Start-ThreadJob  -InitializationScript $init -ScriptBlock $block -ArgumentList $PSScriptRoot -InputObject $config -Name  ("$($config.ResourceGroupName)+$($config.LabPlanName)+$($config.LabName)") -ThrottleLimit $ThrottleLimit
                Start-Sleep -Seconds 1
            }
    
            Write-Verbose "Job count: $($jobs.Count)"
            return JobManager -currentJobs $jobs -ResultColumnName "RemoveLabResult"
        }

        Remove-AzLabs-Jobs -ConfigObject $aggregateLabs
    }
}

function Publish-AzLabsBulk {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab to be created", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [bool]
        $EnableCreatingLabs = $true,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $labs is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs
    }
    end {
        $init = {
            
        }
        function Publish-AzLabs-Jobs {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject
            )

            $block = {
                param($path)

                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'

                Import-Module -Name Az.LabServices

                # Really?? It got to be the lines below? Doing a ForEach doesn't work ...
                $input.movenext() | Out-Null
            
                $obj = $input.current[0]
                $StartTime = Get-Date

                Write-Verbose "object inside the publish-azlab-jobs block $obj"
                
                Write-Host "Start publishing $($obj.LabName)"
                try {
                    $plan = Get-AzLabServicesLabPlan -ResourceGroupName $obj.ResourceGroupName -Name $obj.LabPlanName
                }
                catch {
                    Write-Error "Unable to find lab plan $($obj.LabPlanName)."
                }

                try {
                    $lab = $plan | Get-AzLabServicesLab -Name $obj.LabName
                }
                catch {
                    Write-Error "Unable to find lab $($obj.LabName)."
                }

                Write-Host "Publish state: $($lab.State)"
                if ($lab.State -ne "Failed"){
                    Publish-AzLabServicesLab -Lab $lab | Out-null
                    Write-Host "Completed publishing of $($obj.LabName), total duration $([math]::Round(((Get-Date) - $StartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green
                } else {
                    Write-Host "Unable to publish lab $($lab.Name) state is $($lab.State)"
                }

            }

            Write-Host "Starting publishing of all labs in parallel. Can take a while."
            $jobs = @()

             # Stagger starting threads to avoid Azure KeyStore locked error that an occur when too many threads are started in parallel
             foreach ($config in $ConfigObject) {
                Write-Verbose "From config: $config"
                $jobs += Start-ThreadJob  -InitializationScript $init -ScriptBlock $block -ArgumentList $PSScriptRoot -InputObject $config -Name  ("$($config.ResourceGroupName)+$($config.LabPlanName)+$($config.LabName)") -ThrottleLimit $ThrottleLimit
                Start-Sleep -Seconds 1
            }

            return JobManager -currentJobs $jobs -ResultColumnName "PublishResult" -ConfigObject $ConfigObject
        }
       
        # Added switch to either create labs and publish or just publish existing lab
        # Capture the results so they don't end up on the pipeline
        if ($EnableCreatingLabs) {
            $results = New-AzLabsBulk $aggregateLabs -ThrottleLimit $ThrottleLimit
        }

        # Publish-AzLab-Jobs returns the config object with an additional column, we need to leave it on the pipeline
        Publish-AzLabs-Jobs   -ConfigObject $aggregateLabs
    }
}

function Sync-AzLabADUsersBulk {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab to be created", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5
    )
    
    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $labs is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs
    }
    end {
        $init = {
            
        }
        function Sync-AzLabADUsers-Jobs {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject
            )

            $block = {
                param($path)

                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'

                Import-Module -Name Az.LabServices

                # Really?? It got to be the lines below? Doing a ForEach doesn't work ...
                $input.movenext() | Out-Null
            
                $obj = $input.current[0]
                $StartTime = Get-Date

                Write-Verbose "object inside the Sync-AzLabADUsers-jobs block $obj"
                
                Write-Host "Start ADGroup sync $($obj.LabName)"
                try {
                    Write-Host "Removing Lab: $($obj.LabName)"
                    $plan = Get-AzLabServicesLabPlan -ResourceGroupName $obj.ResourceGroupName -Name $obj.LabPlanName
                }
                catch {
                    Write-Error "Unable to find lab plan $($obj.LabPlanName)."
                }

                try {
                    $lab = $plan | Get-AzLabServicesLab -Name $obj.LabName
                }
                catch {
                    Write-Error "Unable to find lab $($obj.LabName)."
                }

                Sync-AzLabServicesLabUser -Lab $lab | Out-null
                Write-Host "Completed ADGroup sync of $($obj.LabName), total duration $(((Get-Date) - $StartTime).TotalSeconds) seconds" -ForegroundColor Green

            }

            Write-Host "Starting ADGroup sync of all labs in parallel. Can take a while."
            $jobs = @()

            # Stagger starting threads to avoid Azure KeyStore locked error that an occur when too many threads are started in parallel
            foreach ($config in $ConfigObject) {
                Write-Verbose "From config: $config"
                $jobs += Start-ThreadJob  -InitializationScript $init -ScriptBlock $block -ArgumentList $PSScriptRoot -InputObject $config -Name $_.LabName -ThrottleLimit $ThrottleLimit
                Start-Sleep -Seconds 1
            }
    
                Write-Verbose "Job count: $($jobs.Count)"
                return JobManager -currentJobs $jobs -ResultColumnName "SyncUserResult"
        }

        Sync-AzLabADUsers-Jobs   -ConfigObject $aggregateLabs
    }
}

function Get-AzLabsRegistrationLinkBulk {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $labs is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs
    }
    end {
        $init = {
        }

        function Get-RegistrationLink-Jobs {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject
            )

            $block = {
                param($path)

                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'

                Import-Module -Name Az.LabServices

                $input.movenext() | Out-Null
            
                $obj = $input.current[0]

                Write-Host "Getting registration link for $($obj.LabName)"
                try {
                    Write-Host "Get Lab Plan: $($obj.LabPlanName)"
                    $plan = Get-AzLabServicesLabPlan -ResourceGroupName $obj.ResourceGroupName -Name $obj.LabPlanName
                }
                catch {
                    Write-Error "Unable to find lab plan $($obj.LabPlanName)."
                }

                try {
                    $lab = $plan | Get-AzLabServicesLab -Name $obj.LabName
                }
                catch {
                    Write-Error "Unable to find lab $($obj.LabName)."
                }

                Write-Host "Lab: $($lab.SecurityProfileRegistrationCode)"
                $URL = "https://labs.azure.com/register/$($lab.SecurityProfileRegistrationCode)"
                return $URL
            }

            $jobs = @()

            # Stagger starting threads to avoid Azure KeyStore locked error that an occur when too many threads are started in parallel
            foreach ($config in $ConfigObject) {
                Write-Verbose "From config: $config"
                $jobs += Start-ThreadJob  -InitializationScript $init -ScriptBlock $block -ArgumentList $PSScriptRoot -InputObject $config -Name  ("$($config.ResourceGroupName)+$($config.LabPlanName)+$($config.LabName)") -ThrottleLimit $ThrottleLimit
                Start-Sleep -Seconds 1
            }

            return JobManager -currentJobs $jobs -ResultColumnName "RegistrationLinkResult" -ConfigObject $ConfigObject
        }

        # Get-RegistrationLink-Jobs returns the config object with an additional column, we need to leave it on the pipeline
        Get-RegistrationLink-Jobs -ConfigObject $aggregateLabs
    }
}

function Reset-AzLabUserQuotaBulk {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab to be updated.", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $labs is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs

    }
    end {

        $block = {
            param($obj, $path)

            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'

            Write-Verbose "object inside the Update-AzLabUserQuotaBulk-Job block $obj"

            Import-Module -Name Az.LabServices -Force

            Write-Debug "ConfigObject: $($obj | ConvertTo-Json -Depth 40)"
            Write-Host "Checking lab '$($obj.LabName)' for student quotas..."

            $lab = Get-AzLabServicesLab -ResourceGroupName $obj.ResourceGroupName -Name $($obj.LabName)
            if (-not $lab -or @($lab).Count -ne 1) { Write-Error "Unable to find lab $($obj.LabName)."}

            Write-Host "Checking lab '$($lab.Name)' in resource group $($obj.ResourceGroupName) for student quotas..."

            $users = Get-AzLabServicesUser -Lab $lab #-Email "*"

            $totalUserCount = ($users | Measure-Object).Count
            Write-Host "  This lab has '$totalUserCount' users..."
            Write-Host "  Updating the users to have $($obj.UsageQuota) quota remaining..."
            $currentLabQuota = $lab.VirtualMachineProfileUsageQuota #Convert-UsageQuotaToHours($lab.VirtualMachineProfileUsageQuota)
            foreach ($user in $users) {
                $totalUsage = $user.TotalUsage #Convert-UsageQuotaToHours($user.TotalUsage)
                if ($user -contains "additionalUsageQuota") {
                    $currentUserQuota = $user.additionalUsageQuota #Convert-UsageQuotaToHours($user.additionalUsageQuota)
                }
                else {
                    $currentUserQuota = 0
                }

                # if the usage (column from csv) and the available hours are less than the Lab quota set the user quota to zero
                if (($(New-Timespan -Hours $obj.UsageQuota) + $totalUsage) -le $currentLabQuota) {
                    Update-AzLabServicesUser -Lab $lab -Name $user.Name -AdditionalUsageQuota 0 | Out-Null
                } else {
                    #totalUserUsage is the current quota for the lab and the user
                    $totalUserUsage = ($currentLabQuota + $currentUserQuota)
                    #individualUserNeeds is the user used time and the expected available time
                    $individualUserNeeds = (New-Timespan -Hours $obj.UsageQuota) + $totalUsage
                    # subtract totalUserUsage from individualUserNeeds, positives will be added to user quota, negatives removed.
                    $diff = ($individualUserNeeds - $totalUserUsage)
                    #Adjust the current user quota
                    $newuserQuota = $currentUserQuota + $diff
                    if ($newuserQuota -ge 0) {
                        Update-AzLabServicesUser -Lab $lab -Name $user.Name -AdditionalUsageQuota $newuserQuota | Out-Null
                    }
                    else {
                        # Reduce the user quota but only to zero
                        $removeDiff = ($currentUserQuota + $newuserQuota)
                        if ($removeDiff -ge 0) {
                            Update-AzLabServicesUser -Lab $lab -Name $user.Name -AdditionalUsageQuota $removeDiff | Out-Null
                        }
                        else {
                            Update-AzLabServicesUser -Lab $lab -Name $user.Name -AdditionalUsageQuota 0 | Out-Null
                        }
                    }
                }
            }
        }

        $jobs = $aggregateLabs | ForEach-Object {
                Write-Verbose "From config: $_"
                Start-ThreadJob -ScriptBlock $block -ArgumentList $_, $PSScriptRoot -Name $_.LabName -ThrottleLimit $ThrottleLimit
            }

        JobManager -currentJobs $jobs -ResultColumnName "ResetQuotaResult"
    }
}

function Remove-AzLabUsersBulk {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab to be updated.", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $labs is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs

    }
    end {

        $block = {
            param($obj, $path)

            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'

            Write-Verbose "object inside the Remove-AzLabUsersBulk-Job block $obj"

            Import-Module -Name Az.LabServices

            Write-Verbose "ConfigObject: $($obj | ConvertTo-Json -Depth 40)"

            $la = Get-AzLabServicesLabPlan -ResourceGroupName $obj.ResourceGroupName -Name $($obj.LabPlanName)
            if (-not $la -or @($la).Count -ne 1) { Write-Error "Unable to find lab plan $($obj.LabPlanName)."}

            $lab = Get-AzLabServicesLab -LabPlan $la -Name $($obj.LabName)
            if (-not $lab -or @($lab).Count -ne 1) { Write-Error "Unable to find lab $($obj.LabName)."}

            Write-Host "Checking lab '$($lab.Name)' in lab plan '$($la.Name)' for students..."
            
            $students = Get-AzLabServicesUser -LabName $lab.Name -ResourceGroupName $obj.ResourceGroupName

            foreach ($email in $obj.emails) {                
                try {
                    Write-Host "Check user $email"
                    $student = $students | Where-Object {$_.Email -eq $email}
                    Write-Host "Found user $email"
                    if ($student) {
                        Write-Host "Removing user $email"
                        Remove-AzLabServicesUser -Lab $lab -Name $student.Name
                    }
                }
                catch {
                    Write-Host "Unable to find email $email in lab $($lab.Name): $_"
                }                
            }
        }

        $jobs = $aggregateLabs | ForEach-Object {
                Write-Verbose "From config: $_"
                Start-ThreadJob -ScriptBlock $block -ArgumentList $_, $PSScriptRoot -Name $_.LabName -ThrottleLimit $ThrottleLimit
            }

        JobManager -currentJobs $jobs -ResultColumnName "RemoveUserResult"
    }
}

# This function is used to send lab invitations *after* a lab has been created\published - for example, several days\weeks later when student enrollment is finalized.
function Send-AzLabsInvitationBulk {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $labs is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs

    }
    end {
        $init = {            
        }

        function Send-AzLabsInvitation-Jobs {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject
            )

            $block = {
                param($path)

                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'

                Import-Module -Name Az.LabServices

                $input.movenext() | Out-Null
            
                $obj = $input.current[0]
            
                if ($obj.Invitation -and $obj.Emails) { 
                    Write-Host "Sending invitation emails for lab: $($obj.LabName)."
                    $lab = Get-AzLabServicesLab -ResourceGroupName $obj.ResourceGroupName -Name $($obj.LabName)
                    if (-not $lab -or @($lab).Count -ne 1) { Write-Error "Unable to find lab $($obj.LabName)." }

                    $users = Get-AzLabServicesUser -LabName $lab.Name -ResourceGroupName $obj.ResourceGroupName
                    if (($users | Measure-Object).Count -eq 0) { Write-Error "The lab doesn't have any users added." }
                
                    foreach ($user in $users ) {
                        if ($user.InvitationState -eq "NotSent") {
                            Write-Verbose "Sending invitation email to user: $($user.Email)."
                            Send-AzLabServicesUserInvite -ResourceGroupName $obj.ResourceGroupName -LabName $obj.LabName -UserName $user.name -Text $obj.Invitation | Out-Null
                        }
                    }
                }
                else {
                    Write-Error "The invitation and\or user emails are missing for lab in the input .csv file: $($obj.LabName)."
                }
            }

            Write-Host "Sending lab invitations to users.  This may take awhile."
            $jobs = @()

            # Stagger starting threads to avoid Azure KeyStore locked error that an occur when too many threads are started in parallel
            foreach ($config in $ConfigObject) {
                Write-Verbose "From config: $config"
                $jobs += Start-ThreadJob  -InitializationScript $init -ScriptBlock $block -ArgumentList $PSScriptRoot -InputObject $config -Name  ("$($config.ResourceGroupName)+$($config.LabPlanName)+$($config.LabName)") -ThrottleLimit $ThrottleLimit
                Start-Sleep -Seconds 1
            }

            return JobManager -currentJobs $jobs -ResultColumnName "SendInvitationResult" -ConfigObject $ConfigObject
            
         }

         Send-AzLabsInvitation-Jobs -ConfigObject $aggregateLabs 
    }
}

# This function is used to add lab users *after* a lab has been created\published - for example, several days\weeks later when student enrollment is finalized.
function Add-AzLabsUsersBulk {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $labs is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs

    }
    end {
        $init = {            
        }

        function Add-AzLabsUser-Jobs {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject
            )

            $block = {
                param($path)

                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'

                Import-Module -Name Az.LabServices

                $input.movenext() | Out-Null
            
                $obj = $input.current[0]
            
                if ($obj.Emails) { 
                    Write-Host "Adding users for lab: $($obj.LabName)."
                    $lab = Get-AzLabServicesLab -ResourceGroupName $obj.ResourceGroupName -Name $($obj.LabName)
                    if (-not $lab -or @($lab).Count -ne 1) { Write-Error "Unable to find lab $($obj.LabName)." }

                    foreach ($email in $obj.Emails) {  
                        Write-Verbose "Adding user: $email."
                        $user = $null
                        try {
                            $user = Get-AzLabServicesUser -LabName $lab.Name -ResourceGroupName $obj.ResourceGroupName | Where-Object {$_.email -ieq $email}
                            if (!$user) {
                                $tempGuid = New-Guid            
                                $user = New-AzLabServicesUser -Name $tempGuid.Guid.ToString() -LabName $lab.Name -ResourceGroupName $obj.ResourceGroupName -Email $email    
                            }
                        } 
                        catch {
                            $tempGuid = New-Guid            
                            $user = New-AzLabServicesUser -Name $tempGuid.Guid.ToString() -LabName $lab.Name -ResourceGroupName $obj.ResourceGroupName -Email $email    
                        }
                    }
                }
                else {
                    Write-Error "The user emails are missing for lab in the input .csv file: $($obj.LabName)."
                }
            }

            Write-Host "Adding users to lab.  This may take awhile."
            $jobs = @()

            $ConfigObject | ForEach-Object {
            Write-Verbose "From config: $_"
                $jobs += Start-ThreadJob  -InitializationScript $init -ScriptBlock $block -ArgumentList $PSScriptRoot -InputObject $_ -Name ("$($_.ResourceGroupName)+$($_.LabPlanName)+$($_.LabName)") -ThrottleLimit $ThrottleLimit
            }

            return JobManager -currentJobs $jobs -ResultColumnName "AddUserResult" -ConfigObject $ConfigObject
         }

         Add-AzLabsUser-Jobs -ConfigObject $aggregateLabs 
    }
}

function Confirm-AzLabsBulk {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $ThrottleLimit = 5,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('Created', 'Published')]
        [string]
        $ExpectedLabState = 'Created'
    )

    begin {
        # This patterns aggregates all the objects in the pipeline before performing an operation
        # i.e. executes lab creation in parallel instead of sequentially
        # This trick is to make it work both when the argument is passed as pipeline and as normal arg.
        # I came up with this. Maybe there is a better way.
        $aggregateLabs = @()
    }
    process {
        # If passed through pipeline, $labs is a single object, otherwise it is the whole array
        # It works because PS uses '+' to add objects or arrays to an array
        $aggregateLabs += $labs
    }
    end {
        $init = {
        }

        function Validate-AzLab-Jobs {
            [CmdletBinding()]
            param(
                [parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [psobject[]]
                $ConfigObject
            )

            $block = {
                param($path, $expectedLabState)

                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'

                
                Import-Module -Name Az.LabServices

                $input.movenext() | Out-Null
            
                $obj = $input.current[0]

                Write-Host "Validating properties for $($obj.LabName)"

                # Lab Plan Exists
                $plan = Get-AzLabServicesLabPlan -ResourceGroupName $obj.ResourceGroupName -Name $obj.LabPlanName
                if (-not $plan) {
                    Write-Error "Lab Plan doesn't exist..."
                }
                if ($plan.provisioningState -ine "Succeeded") {
                    Write-Error "Lab Plan didn't provision successfully"
                }

                # Lab Plan has shared gallery and image enabled
                if ((Get-Member -InputObject $obj -Name 'SharedGalleryId') -and $obj.SharedGalleryId) {
                    #$sharedGallery = Get-AzLabPlanSharedGallery -LabPlan $la
                    if (-not $plan.SharedGalleryId) {
                        Write-Error "Shared Gallery not attached correctly"
                    }
                }

                # Lab Exists
                $lab = Get-AzLabServicesLab -LabPlan $plan -Name $obj.LabName
                if (-not $lab) {
                    Write-Error "Lab doesn't exist..."
                }

                if ($lab.provisioningState -ine "Succeeded") {
                    Write-Error "Lab Account didn't provision successfully"
                }

                # Lab Max users 
                if ((Get-Member -InputObject $obj -Name 'MaxUsers') -and $obj.MaxUsers) {
                    if ($obj.MaxUsers -ne $lab.SkuCapacity) {
                        Write-Error "Max users don't match for this lab"
                    }
                }

                # AAD Group Id (if set) is correct
                if ((Get-Member -InputObject $obj -Name 'AadGroupId') -and $obj.AadGroupId) {
                    if ($obj.AadGroupId -ine $lab.aadGroupId) {
                        Write-Error "AAD Group Id doesn't match for this lab"
                    }
                }

                # Usage Mode is correct
                if ($obj.UsageMode) {
                    if ($obj.UsageMode -ine $lab.SecurityProfileOpenAccess) {
                        Write-Error "UsageMode doesn't match for this lab..."
                    }
                }

                # Validate the template settings (disabled/enabled) and provisioningState
                $template = $lab | Get-AzLabServicesTemplateVm

                if (($lab.VirtualMachineProfileCreateOption -eq "TemplateVM") -and (-not $template)) {
                    Write-Error "Template doesn't exist for lab, the lab is broken..."
                } elseif (($lab.VirtualMachineProfileCreateOption -eq "TemplateVM")) {
                    if ($template.provisioningState -ine "Succeeded") {
                        Write-Error "Template object failed to be created for lab, the lab is broken..."
                    }
                    # Validate the username is correct for accounts
                    if ($obj.UserName -ine $template.ConnectionProfileAdminUserName) {
                        Write-Error "Username is incorrect in the lab template object..."
                    }
                }

                # Validate the VM size is set corectly
                if ($obj.Size -ine $lab.SkuName) {
                    Write-Error "VM Size is not set correctly in the lab"
                }

                # Write something to the UI after checking lab settings
                Write-Host "Lab and template settings appear correct.."

                if ($expectedLabState -ieq "Published")
                {
                    # If we expect the lab to be published, validate the state of the template and student VMs
                    Write-Host "Template's publishing state is: $($lab.properties.State)"
                    if ($lab.State -ne "Published") {
                        Write-Error "Publishing lab template failed"
                    }

                    # maxUsers is empty if using AAD groups, so compare against the max users in the lab
                    $vms = $lab | Get-AzLabVm -Status "Any"
                    if (($vms | Measure-Object).Count -ne $lab.SkuCapacity) {
                        Write-Error "Unexpected number of VMs"
                    }
    
                    $publishedVms = $vms | Where-Object { $_.provisioningState -ieq "Succeeded" }
                    if (($publishedVMs | Measure-Object).Count -ne $lab.SkuCapacity) {
                        Write-Error "Unexpected number of VMs in succeeded state"
                    }
                }
        
            }

            $jobs = @()

             # Stagger starting threads to avoid Azure KeyStore locked error that an occur when too many threads are started in parallel
             foreach ($config in $ConfigObject) {
                Write-Verbose "From config: $config"
                $jobs += Start-ThreadJob  -InitializationScript $init -ScriptBlock $block -ArgumentList $PSScriptRoot -InputObject $config -Name  ("$($config.ResourceGroupName)+$($config.LabPlanName)+$($config.LabName)") -ThrottleLimit $ThrottleLimit
                Start-Sleep -Seconds 1
            }

            return JobManager -currentJobs $jobs -ResultColumnName "ConfirmLabResult" -ConfigObject $ConfigObject
        }

        # Get-RegistrationLink-Jobs returns the config object with an additional column, we need to leave it on the pipeline
        Validate-AzLab-Jobs -ConfigObject $aggregateLabs
    }
}

function JobManager {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array of jobs to manage", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject[]]
        $currentjobs,

        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $ResultColumnName,

        [parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [psobject[]]
        $ConfigObject
    )

            $jobs = $currentjobs
            while (($jobs | Measure-Object).Count -gt 0) {
                # If we have more jobs, wait for 60 sec before checking job status again
                Start-Sleep -Seconds 20
                $allCompletedJobs = $jobs | Where-Object {($_.State -ieq "Completed") -or ($_.State -ieq "Failed")}
                if (($allCompletedJobs | Measure-Object).Count -gt 0) {

                    # Write output for completed jobs, but one by one so output doesn't bleed 
                    # together, also use "Continue" so we write the error but don't end the outer script
                    $allCompletedJobs | ForEach-Object {
                        #$URL = $_ | Receive-Job -ErrorAction Continue
                        if ($ConfigObject) {
                            # For each completed job we write the result back to the appropriate Config object, using the "name" field to coorelate

                            $jobName = $_.Name
                            $jobState = $_.State
                            if (($jobName.ToCharArray() | Where-Object {$_ -eq '+'} | Measure-Object).Count -gt 1)
                            {
                                $config = $ConfigObject | Where-Object {$_.ResourceGroupName -ieq $jobName.Split('+')[0] -and $_.LabPlanName -ieq $jobName.Split('+')[1] -and $_.LabName -ieq $jobName.Split('+')[2]}
                            } else {
                                $config = $ConfigObject | Where-Object {$_.ResourceGroupName -ieq $jobName.Split('+')[0] -and $_.LabPlanName -ieq $jobName.Split('+')[1]}
                            }
                            
                            $config | ForEach-Object {
                                if (Get-Member -InputObject $config -Name $ResultColumnName) {
                                    $_.$ResultColumnName = $jobState
                                }
                                else {
                                    Add-Member -InputObject $_ -MemberType NoteProperty -Name $ResultColumnName -Value $jobState -Force
                                }
                            }
                        }
                        $_ | Receive-Job -ErrorAction Continue
                    }
                    # Trim off the completed jobs from our list of jobs
                    $runningJobs = $jobs | Where-Object {$_.Id -notin $allCompletedJobs.Id}
                    
                    if ($runningJobs) {
                        $jobs = $runningJobs
                    } else {
                        $jobs = $null
                    }
                    # Remove the completed jobs from memory
                    $allCompletedJobs | Remove-Job
                }
            }
            # Return the objects with an additional property on the result of the operation
            return $ConfigObject
}

function Set-LabProperty {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab to be created", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [Parameter(Mandatory = $true, ValueFromRemainingArguments=$true, HelpMessage = "Series of multiple -propertyName propValue pairs")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $vars
    )
    begin {
        #Convert vars to hashtable
        $htvars = @{}
        $vars | ForEach-Object {
            if($_ -match '^-') {
                #New parameter
                Write-Verbose $_
                $lastvar = $_ -replace '^-'
                $lastvar = $lastvar -replace ':' # passing parameters as hashtable inserts a : char
                $htvars[$lastvar] = $null
            } else {
                #Value
                $htvars[$lastvar] = $_
            }
        }
    }

    process {
        foreach ($l in $labs) {
            # Deep cloning not to change the original
            $lc = [System.Management.Automation.PSSerializer]::Deserialize(
                    [System.Management.Automation.PSSerializer]::Serialize($l))

            Write-Verbose ($lc | Out-String) 

            function ChangeLab ($lab) {
                $htvars.Keys | ForEach-Object { $lab.($_) = $htvars[$_]}
            }
            $lc | ForEach-Object { ChangeLab  $_}
            $lc
        }
    }
}

function Show-LabMenu {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab to be created", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [Parameter(Mandatory = $false, HelpMessage = "Pick one lab from the labs' list")]
        [switch]
        $PickLab,

        [Parameter(Mandatory = $false, HelpMessage = "Which lab properties to show a prompt for")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Properties
    )

    begin {

        function LabToString($lab, $index) {
            return "[$index]`t$($lab.Id)`t$($lab.ResourceGroupName)`t$($lab.LabName)"
        }

        $propsPassed = $PSBoundParameters.ContainsKey('Properties')
        $pickLabPassed = $PSBoundParameters.ContainsKey('PickLab')

        if($pickLabPassed) {
           Write-Host "LABS"
        }

        $aggregateLabs = @()
    }
    process {
        $aggregateLabs += $labs
    }
    end {

        if($pickLabPassed) {
            $index = 0
            $aggregateLabs | ForEach-Object { Write-Host (LabToString $_ ($index++)) }

            $resp = $null
            do {
                $resp = Read-Host -Prompt "Please select the lab to create"
                $resp = $resp -as [int]
                if($resp -eq $null) {
                    Write-Host "Not an integer.Try again." -ForegroundColor red
                }
                if($resp -and ($resp -ge $labs.Length -or $resp -lt 0)) {
                    Write-Host "The lab number must be between 0 and $($labs.Length - 1). Try again." -ForegroundColor red
                    $resp = $null
                }
            } until ($resp -ne $null)
            $aggregateLabs = ,$aggregateLabs[$resp]
        }

        if($propsPassed) {
            $hash = @{}
            $properties | ForEach-Object { $hash[$_] = Read-Host -Prompt "$_"}

            $aggregateLabs = $aggregateLabs | Set-LabProperty @hash
        }
        return $aggregateLabs
    }
}

# I am forced to use parameter names starting with 'An' because otherwise they get
# bounded automatically to the fields in the CSV and added to $PSBoundParameters
function Select-Lab {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, HelpMessage = "Array containing one line for each lab to be created", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [psobject[]]
        $labs,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = "Id to look for")]
        [string]
        $AnId,

        [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = "If a lab contains any of these tags, it will be selected")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $SomeTags
    )

    begin {
        function HasAnyTags($foundTags) {
            $found = $false
            $SomeTags | ForEach-Object {
                if(($foundTags -split ';') -contains $_) {
                    $found = $true
                }
            }
            return $found
        }
    }
    process {

        $labs | ForEach-Object {
            Write-Verbose ($PSBoundParameters | Out-String)
            $IdPassed = $PSBoundParameters.ContainsKey('AnId')
            $TagsPassed = $PSBoundParameters.ContainsKey('SomeTags')
            $IdOk = (-not $IdPassed) -or ($_.Id.Trim() -eq $AnId)
            $TagsOk = (-not $TagsPassed) -or (HasAnyTags($_.Tags))

            Write-Verbose "$IdPassed $TagsPassed $IdOk $TagsOk"

            if($IdOk -and $TagsOk) {
                return $_
            }
        }
    }
}

Export-ModuleMember -Function   Import-LabsCsv,
                                New-AzLabsBulk,
                                New-AzLabPlansBulk,
                                Remove-AzLabsBulk,
                                Publish-AzLabsBulk,
                                Sync-AzLabADUsersBulk,
                                Get-AzLabsRegistrationLinkBulk,
                                Reset-AzLabUserQuotaBulk,
                                Remove-AzLabUsersBulk,
                                Confirm-AzLabsBulk,
                                Set-AzRoleToLabPlansBulk,
                                Set-LabProperty,
                                Set-LabPropertyByMenu,
                                Select-Lab,
                                Show-LabMenu,
                                Export-LabsCsv,
                                Send-AzLabsInvitationBulk,
                                Add-AzLabsUsersBulk