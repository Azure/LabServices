# Lets stop the script for any errors
$ErrorActionPreference = "Stop"

# ************************************************
# ************ FIELDS TO UPDATE ******************
# ************************************************

# List of lab names that we should not include when updating quota)
$excludeLabs = @('*test*','*demo*','*training*', '*how to*')

# Number of available hours we reset the student to when running this script
$usageQuota = 8

# Segment of labs to update based on lab plans, regular expression to match

# Match for all lab plans   
$labPlanNameRegex = "^.*"

# Subscription ID
$subId = "1111-1111-1111-11111-11111111"

# ************************************************

if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-Module -Name AzureRM -ListAvailable)) {
    #    Write-Warning -Message ('Az module not installed. Having both the AzureRM and ' +
    #      'Az modules installed at the same time is not supported.')
    } else {
        Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force -Confirm:$false
    }

# Install the Az.LabServices module if the command isn't available
if (-not (Get-Command -Name "Get-AzLabServicesLab" -ErrorAction SilentlyContinue)) {
    Install-Module -Name Az.LabServices -Scope CurrentUser -Force
}

Import-Module Az

$relativePath = "..\BulkOperations\Az.LabServices.BulkOperations.psm1"
$currentDirPath = Join-Path -Path (Get-Location) -ChildPath "Az.LabServices.BulkOperations.psm1"

if (Test-Path -Path $relativePath) {
    Import-Module $relativePath -Force
} elseif (Test-Path -Path $currentDirPath) {
    Import-Module $currentDirPath -Force
} else {
    Write-Error "BulkOperations.psm1 not found in the provided relative path or the current directory."
    return
}

Connect-AzAccount -Subscription $subId -Identity
Write-Output "Lab quota update start at $(Get-Date)"

# create a temp file for host output
$dateString = Get-Date -Format "yyyyMMdd_HHmmss"
$tempFilePath = Join-Path -Path $env:TEMP -ChildPath "AzureLabsUserQuota_$dateString.txt"
$hostOutputFile = New-Item -Path $tempFilePath -ItemType File -Force

$labPlans = Get-AzLabServicesLabPlan | Where-Object {
    $_.Name -match $labPlanNameRegex
}
Write-Output " Found .. $(($labPlans | Measure-Object).Count) lab plans)"

Write-Output "  Temp file location is: $($HostOutputFile.FullName)"

try {
    $scriptstartTime = Get-Date
    Write-Output "Executing Bulk User Quota Script, starting at $scriptstartTime"

    $labPlans = Get-AzLabServicesLabPlan | Where-Object {
        $_.Name -match $labPlanNameRegex
    }
    
    $labs = $labPlans | Get-AzLabServicesLab 6>> $HostOutputFile.FullName

    # Filter the labs down to only the set that we should update
    Write-Output "Checking for labs to exclude..." 6>> $HostOutputFile.FullName
    $labsToUpdate = $labs | Where-Object {
        $toExclude = $null
        $labName = $_.Name
        $toExclude = $excludeLabs | ForEach-Object {
            if ($labName -like $_) {$true}
        }
        if ($toExclude) 
            {
                # Can't write output to the hostfile because it breaks the filtering, so we'll just write to the terminal
                Write-Host "excluding $labName "
                $false
            } 
        else {$true}
    }

    $labsToUpdate | ForEach-Object {
		Write-Output "Add member $($_.Name)"
        Add-Member -InputObject $_ -MemberType NoteProperty -Name "UsageQuota" -Value $usageQuota -Force
        Add-Member -InputObject $_ -MemberType NoteProperty -Name "LabName" -Value $_.Name -Force
        Add-Member -InputObject $_ -MemberType NoteProperty -Name "ResourceGroupName" -Value $_.Id.Split("/")[4] -Force
    }

    # Now - let's call the bulk update function to update all the labs, piping 'host' messages to a file
    $labsToUpdate | Reset-AzLabUserQuotaBulk -ThrottleLimit 5  6>> $hostOutputFile.FullName
}
catch {
    # We just rethrow any errors with original context
    throw
}
finally {
    # Read in the 'host' messages and show them in the output
    Get-Content -Path $hostOutputFile.FullName
}

Write-Output "Completed running Bulk User Quota script, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes"
