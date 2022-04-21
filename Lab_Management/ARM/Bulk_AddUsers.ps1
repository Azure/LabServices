[CmdletBinding()]
param(
    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CsvConfigFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Make sure the input file does exist
if (-not (Test-Path -Path $CsvConfigFile)) {
    Write-Error "Input CSV File must exist, please choose a valid file location..."
}

Import-Module ".\Utilities.psm1"

$scriptuserstartTime = Get-Date
Write-Host "Executing Bulk Add Users script, starting at $scriptuserstartTime" -ForegroundColor Green

$labs = Import-LabsCsv $CsvConfigFile

ForEach ($lab in $labs) {
    try {
        if (![bool]$lab.PSObject.Properties.Item("Emails")) {
            Write-Host "Adding users to lab $($lab.LabName)"
            New-AzLabServicesUser -Name $(New-Guid) -LabName $lab.LabName -ResourceGroupName $lab.ResourceGroupName -Email $lab.Emails -AsJob
        }
    } catch {        
        Write-Host "Unable to add users to Lab: $($lab.LabName) in $($lab.ResourceGroupName): Error message: $_"
    }
}

Write-Host "Completed running Bulk Add Users script, total duration $([math]::Round(((Get-Date) - $scriptuserstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green