[CmdletBinding()]
param(
    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CsvConfigFile,

    [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Make sure the input file does exist
if (-not (Test-Path -Path $CsvConfigFile)) {
    Write-Error "Input CSV File must exist, please choose a valid file location..."
}

Import-Module ../Az.LabServices.BulkOperations.psm1 -Force

$scriptstartTime = Get-Date
Write-Host "Executing Lab Account Deletion Script, starting at $scriptstartTime" -ForegroundColor Green

$configObjects = $CsvConfigFile | Import-Csv
$labPlans = $configObjects | Select-Object -Property ResourceGroupName, LabPlanName -Unique

$labPlans | ForEach-Object {
    $labPlan = Get-AzLabServicesLabPlan -ResourceGroupName $_.ResourceGroupName -LabPlanName $_.LabPlanName -ErrorAction SilentlyContinue
    if ($labPlan) {
        $labPlan | Remove-AzLabServicesLabPlan
        Write-Host "Initiated removing Lab plan '$($_.LabPlanName)' in resource group '$($_.ResourceGroupName)'"
    }
    else {
        Write-Host "Lab Plan '$($_.LabPlanName)' in resource group '$($_.ResourceGroupName)' doesn't exist, cannot delete..."
    }
}

Write-Host "Completed running Lab Plan deletion, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green
