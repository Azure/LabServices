[CmdletBinding()]
param(
    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CsvConfigFile,

    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $LMSInstance,

    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $LTIClientId,

    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $developerKeyToken,

    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CsvOutputFile,

    [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [switch] $force,

    [parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [int] $ThrottleLimit = 10
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

Import-Module .\Lab_Management\PowerShell\BulkOperations\Az.LabServices.BulkOperations.psm1 -Force

$scriptstartTime = Get-Date
Write-Host "Executing Canvas Lab Creation Script, starting at $scriptstartTime" -ForegroundColor Green

$labs = .\GetCanvasLabInformation.ps1 -CsvConfigFile $CsvConfigFile -LMSInstance $LMSInstance -LTIClientId $LTIClientId -developerKeyToken $developerKeyToken

foreach ($lab in $labs) {
    $x = $lab.LabName.Replace(" ","_")
    $lab | Add-Member -MemberType NoteProperty -Name LabName -Value $x -Force
}

$labs | New-AzLabsBulk -ThrottleLimit $ThrottleLimit

$labs | Export-LabsCsv -CsvConfigFile $CsvOutputFile -Force:$force.IsPresent

Write-Host "Completed running Bulk Lab Creation script, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green
