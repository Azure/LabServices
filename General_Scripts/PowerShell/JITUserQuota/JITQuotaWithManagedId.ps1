# Lets stop the script for any errors
$ErrorActionPreference = "Stop"

# ************************************************
# ************ FIELDS TO UPDATE ******************
# ************************************************

# List of lab names that we should not include when updating quota)
$excludeLabs = @('*test*','*demo*','*training*', '*how to*')

# Number of available hours we reset the student to when running this script
$usageQuota = 9

# Segment of labs to update based on lab accounts, regular expression to match

# Match for all lab plans
$labPlanNameRegex = "^.*"

# ************************************************

# create a temp file for host output
$hostOutputFile = New-TemporaryFile

Write-Output "Connecting service connection to Azure resources..."
# Ensures you inherit azcontext in your Azure Automation runbook
Enable-AzContextAutosave -Scope Process

# Setup Azure Runbook Connection using System ManagedId
try {
        $AzureContext = (Connect-AzAccount -Identity).context
    }
catch{
        Write-Output "There is no system-assigned user identity. Aborting."; 
        exit
    }

# set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription `
    -DefaultProfile $AzureContext

# Make sure we have the modules already imported via the automation account
if (-not (Get-Command -Name "Get-AzLabServicesLabPlan" -ErrorAction SilentlyContinue)) {
    Write-Error "Unable to find the Az.LabServices.psm1 module, please add to the Azure Automation account"
}
if (-not (Get-Command -Name "Reset-AzLabUserQuotaBulk" -ErrorAction SilentlyContinue)) {
    Write-Error "Unable to find the Az.LabServices.BulkOperations.psm1 module, please add to the Azure Automation account"
}
if (-not (Get-Command -Name "Start-ThreadJob" -ErrorAction SilentlyContinue)) {
    Write-Error "Unable to find the ThreadJob Powershell module, please add to the Azure Automation account"
}

# -DefaultProfile $AzureContext
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
        Write-Host "xxx: $($_.Name)"
        $toExclude = $null
        $labName = $_.Name
        $toExclude = $excludeLabs | ForEach-Object {
            if ($labName -like $_) {$true}
        }
        if ($toExclude) 
            {
                Write-Output "   Excluding Lab '$labName'" 6>> $HostOutputFile.FullName
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
    # Make sure we get the output back to Azure Automation, even if something breaks

    # Read in the 'host' messages and show them in the output
    Get-Content -Path $hostOutputFile.FullName

    # Remove the temp output file
    Remove-Item -Path $HostOutputFile.FullName -Force
}

Write-Output "Completed running Bulk User Quota script, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes"