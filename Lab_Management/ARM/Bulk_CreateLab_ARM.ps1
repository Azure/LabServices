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
    [string] $ARMFile,

    [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [switch] $publish,

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

Import-Module ".\Utilities.psm1" -Force

$scriptstartTime = Get-Date
Write-Host "Executing Lab Creation Script, starting at $scriptstartTime" -ForegroundColor Green

$labs = $CsvConfigFile | Import-LabsCsv 

$jobs = @{}

ForEach ($lab in $labs) {
    
    # Reduce image get cost.
    if (-not [boolean](Get-Variable $($lab.LabPlanName) -ErrorAction SilentlyContinue)) {
        Write-Host "Getting new images $($lab.LabPlanName)"
        New-Variable -Name $lab.LabPlanName -Value $(Get-AzLabServicesPlanImage -ResourceGroupName $lab.ResourceGroupName -LabPlanName $lab.LabPlanName)
    }
    
    #Handle tags
    $tagParam = @{}
    if ($lab.Tags) {
        $tags = $lab.Tags.Split(";")
        foreach($tag in $tags) {
            $tagParts = $tag.Split("=")
            $tagParam.Add($tagParts[0],$tagParts[1])
        }
    }


    $hashParam = @{LabName = $($lab.LabName); `
        Title = $($lab.Title); `
        Tags = $($tagParam); `
        LabPlanName = $($lab.LabPlanName); `
        Location = $($lab.Location); `
        AadGroupId = $($lab.AadGroupId); `
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

    #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Create Users array
        $hashParam.Add("LabUsers", $lab.Emails)
    #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Create Schedules Array
        $scheduleArray = @()
        if ($lab.Schedules) {
            foreach($schedule in $lab.Schedules) {
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

                $weekdays = @() #$null
                foreach ($day in ($schedule.WeekDays -Split ";")) {
                    $weekdays += $day.Trim("""").ToString()
                }


                    if ($schedule.Frequency -eq "Once") {
                        $singleEvent = @{
                            startAt = $fullStart
                            stopAt = $fullEnd
                            timeZoneId = $($schedule.TimeZoneId)
                            notes = $($schedule.Notes)
                        }
                        $scheduleArray += $singleEvent
                    } else {
                        $repeatEvent = @{
                            startAt = $fullStart
                            stopAt = $fullEnd
                            timeZoneId = $($schedule.TimeZoneId)
                            notes = $($schedule.Notes)
                            recurrencePattern = @{
                                frequency = $($schedule.Frequency)
                                weekDays = $weekdays
                                interval = 1
                                expirationDate = $(Get-Date $fullUntil)
                            }
                        }
                        $scheduleArray += $repeatEvent
                    }
            }
            $hashParam.Add("LabSchedules", $scheduleArray)
        } else {
            $hashParam.Add("LabSchedules", @())
        }
    #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    Write-Host "Start creating lab $($lab.LabName)"
    $key = $lab.ResourceGroupName + ":" + $lab.LabName
    $value = New-AzResourceGroupDeployment -Name $lab.LabName -AsJob -ResourceGroupName $($lab.ResourceGroupName) -TemplateFile $ARMFile -TemplateParameterObject $hashParam | Get-Job
    $jobs.Add($key,$value)

}

Watch-Jobs -Labs $labs -Jobs $jobs -ResultColumnName "CreateLabResult" | Out-Null

Write-Host "All Labs Creation finished, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green

$labs | Export-LabsCsv -CsvConfigFile $CsvOutputFile -Force:$true


#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if ($true) {
#if ($publish.IsPresent) {
    $jobs = @{}
    $pubscriptstartTime = Get-Date
    Write-Host "Executing Lab Creation Publish Script, starting at $pubscriptstartTime" -ForegroundColor Green

    foreach ($lab in $labs) {    
        $key = $lab.ResourceGroupName + ":" + $lab.LabName
        $value = Publish-AzLabServicesLab -Name $lab.LabName -ResourceGroupName $lab.ResourceGroupName -AsJob | Get-Job
        $jobs.Add($key,$value)
    }

    Watch-Jobs -Labs $labs -Jobs $jobs -ResultColumnName "PublishLabResult" | Out-Null
    $labs | Export-LabsCsv -CsvConfigFile $CsvOutputFile -Force:$true
    Write-Host "Lab Publish finished, total duration $([math]::Round(((Get-Date) - $pubscriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green

}

Write-Host "Completed running Bulk Lab ARM Creation script, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green

