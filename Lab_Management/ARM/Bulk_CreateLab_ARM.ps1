[CmdletBinding()]
param(
    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CsvConfigFile,

    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CsvOutputFile,

    [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ARMFile = "C:\Repos\LabServices\Lab_Management\ARM\LabTemplate_Sample.json",

    [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [switch] $force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Make sure the input file does exist
if (-not (Test-Path -Path $CsvConfigFile)) {
    Write-Error "Input CSV File must exist, please choose a valid file location..."
}

# Make sure the output file doesn't exist
if ((Test-Path -Path $CsvOutputFile) -and (-not $force.IsPresent)) {
    Write-Error "Output File cannot already exist, please choose a location to create a new output file..."
}

Import-Module ".\Utilities.psm1"

$scriptstartTime = Get-Date
Write-Host "Executing Lab Creation Script, starting at $scriptstartTime" -ForegroundColor Green

$labs = $CsvConfigFile | Import-LabsCsv 

$jobs = @()

ForEach ($lab in $labs) {
    
    # Reduce image get cost.
    if (-not [boolean](Get-Variable $($lab.LabPlanName) -ErrorAction SilentlyContinue)) {
        Write-Host "Getting new images $($lab.LabPlanName)"
        New-Variable -Name $lab.LabPlanName -Value $(Get-AzLabServicesPlanImage -ResourceGroupName $lab.ResourceGroupName -LabPlanName $lab.LabPlanName)
    }

    $hashParam = @{LabName = $($lab.LabName); `
        LabPlanName = $($lab.LabPlanName); `
        Location = $($lab.Location); `
        SkuSize = $($lab.Size); `
        Capacity = [int]$($lab.MaxUsers); `
        UsageQuota = $($lab.UsageQuota); `
        SharedPassword = $($lab.SharedPassword); `
        DisconnectDelay = $(if ($lab.idleOsGracePeriod) {$lab.idleOsGracePeriod} else {"0"}); `
        NoConnectDelay = $( if ($lab.idleNoConnectGracePeriod) {$lab.idleNoConnectGracePeriod} else {"0"}); `
        IdleDelay = $(if ($lab.idleGracePeriod) {$lab.idleGracePeriod} else {"0"}); `
        AdminUser = $($lab.UserName); `
        AdminPassword = $($lab.Password); }

    if ($lab.GpuDriverEnabled -eq "Enabled") {
        $hashParam.Add("GpuDrivers", "Enabled")
    } else {
        $hashParam.Add("GpuDrivers", "Disabled")
    }

    if ($lab.UsageMode -eq "Restricted"){
        $hashParam.Add("SecurityOpenAccess","Disabled")
    } else {
        $hashParam.Add("SecurityOpenAccess","Enabled")
    }
    
    if ($lab.SharedGalleryId) {

        $image = Get-AzGalleryImageDefinition -ResourceId $lab.SharedGalleryId
        $hashParam.Add("ImageOffer", $image.Identifier.Offer)
        $hashParam.Add("ImagePublisher", $image.Identifier.Publisher)
        $hashParam.Add("ImageSku", $image.Identifier.Sku)
        $hashParam.Add("ImageVersion", "latest")
    } else {
        $images = Get-Variable -Name $lab.LabPlanName -ValueOnly
        $image = $images | Where-Object { ($_.DisplayName -eq $lab.ImageName) -and ($_.EnabledState.ToString() -eq "Enabled")}
        if (-not ($image)) {
            Write-Host "Unable to find an image with display name $($lab.ImageName)"
            exit
        }
        if (($image | Measure-Object).Count -gt 1) {
            Write-Host "Found multiples images with display name $($lab.ImageName)"
            exit
        }
        if ($image.EnabledState.ToString() -ne "Enabled") {
            Write-Host "Image $($image.DisplayName) not enabled, enabling."
            Update-AzLabServicesPlanImage -LabPlanName $lab.LabPlanName -ResourceGroupName $lab.ResourceGroupName -Name $image.Name -EnabledState "Enabled"
            New-Variable -Name $lab.LabPlanName -Value $(Get-AzLabServicesPlanImage -ResourceGroupName $lab.ResourceGroupName -LabPlanName $lab.LabPlanName) -Force
        }

        $hashParam.Add("ImageOffer", $image.Offer)
        $hashParam.Add("ImagePublisher", $image.Publisher)
        $hashParam.Add("ImageSku", $image.Sku)
        $hashParam.Add("ImageVersion", $image.Version)
    }
    $jobs +=New-AzResourceGroupDeployment -Name $lab.LabName -AsJob -ResourceGroupName $($lab.ResourceGroupName) -TemplateFile $ARMFile -TemplateParameterObject $hashParam | Get-Job
}

$jobs | Wait-Job
Write-Host "Lab Creation finished, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green

foreach ($job in $jobs) {
   
    if ((![bool]$job.PSObject.Properties.Item("Output")) -or (-not [string]::IsNullOrEmpty($job.Error))) { 
        #Parse the Name to get the lab name
        $labName = $job.Name.Split("'")[3]
        $labjob = $labs | Where-Object { ($_.LabName -eq $labName)}
        if ($labjob) {
            Add-Member -InputObject $labjob -MemberType NoteProperty -Name "CreateLabResult" -Value "Failed: $($job.Error)" -Force
        }
    }
    else {
        $labjob = $labs | Where-Object { ($_.ResourceGroupName -eq $job.Output.ResourceGroupName) -and ($_.LabName -eq $job.Output.DeploymentName)}

        if ($labjob) {
            Add-Member -InputObject $labjob -MemberType NoteProperty -Name "CreateLabResult" -Value "Success" -Force
        }
        Remove-Job -Job $job
    }
}

Write-Host "Completed running Bulk Lab Creation script, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green

$labs | Export-LabsCsv -CsvConfigFile $CsvOutputFile -Force:$true

Write-Host "Adding Users"

. .\Bulk_AddUsers.ps1 -CsvConfigFile $CsvConfigFile

Write-Host "Adding Schedules"

. .\Bulk_AddSchedules.ps1 -CsvConfigFile $CsvConfigFile

Write-Host "Completed running Bulk Lab ARM Creation script, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green

