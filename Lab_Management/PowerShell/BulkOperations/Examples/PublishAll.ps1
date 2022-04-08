[CmdletBinding()]
param(
    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string]
    $CsvConfigFile,

    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string]
    $CsvOutputFile,

    [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [switch] $force,

    [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [int]
    $ThrottleLimit = 10
)

# Make sure the input file does exist
if (-not (Test-Path -Path $CsvConfigFile)) {
    Write-Error "Input CSV File must exist, please choose a valid file location..."
}

# Make sure the output file doesn't exist
if ((Test-Path -Path $CsvOutputFile) -and (-not $force.IsPresent)) {
    Write-Error "Output File cannot already exist, please choose a location to create a new output file..."
}

$outerScriptstartTime = Get-Date
Write-Host "Executing Lab Creation Script, starting at $outerScriptstartTime" -ForegroundColor Green

Import-Module ../Az.LabServices.BulkOperations.psm1 -Force

$labAccountResults = $CsvConfigFile | 
        Import-LabsCsv |                                      # Import the CSV File into objects, including validation & transforms
        New-AzLabPlansBulk -ThrottleLimit $ThrottleLimit | # Create all the lab accounts
        New-AzLabsBulk -ThrottleLimit $ThrottleLimit |        # Create all labs
        Publish-AzLabsBulk -ThrottleLimit $ThrottleLimit      # Publish all the labs

# Write out the results
$labAccountResults | Export-LabsCsv -CsvConfigFile $CsvOutputFile -Force:$force.IsPresent
$labAccountResults | Select-Object -Property ResourceGroupName, LabPlanName, LabName, LabPlanResult, LabResult, PublishResult | Format-Table

Write-Host "Completed running Bulk Lab Creation script, total duration $(((Get-Date) - $outerScriptstartTime).TotalMinutes) minutes" -ForegroundColor Green
