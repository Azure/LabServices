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

$scriptstartTime = Get-Date
Write-Host "Executing Bulk Publish Script, starting at $scriptstartTime" -ForegroundColor Green

$labs = Import-LabsCsv $CsvConfigFile

$jobs = @()
$jobs += $labs | ForEach-Object {Remove-AzLabServicesLab -Name $_.LabName -ResourceGroupName $_.ResourceGroupName -AsJob} | Get-Job

$jobs | Wait-Job

Write-Host "Completed running Remove Labs script, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green