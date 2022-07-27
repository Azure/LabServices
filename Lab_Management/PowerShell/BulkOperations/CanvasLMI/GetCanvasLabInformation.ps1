
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
    [string] $developerKeyToken
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
Write-Host "Executing Canvas conversion script, starting at $scriptstartTime" -ForegroundColor Green

$header = @{
    'Content-Type'  = 'application/json'
    "Authorization" = "Bearer " + $developerKeyToken
    "Accept"        = "application/json;odata=fullmetadata"
}


$labs = $CsvConfigFile | Import-LabsCsv 

# Get the course id for each lab then update the labs
$FullUri = "$($LMSInstance)api/v1/courses?per_page=1000"

# Get the course id where the names match
$result = Invoke-WebRequest -Uri $FullUri -Method 'Get' -Headers $header -UseBasicParsing

$canvasLabs = $result.Content | ConvertFrom-Json

foreach ($lab in $labs) {
    Write-Debug "Lab: $($lab.LabName)"
    foreach ($canvasLab in $canvasLabs) {
        Write-Debug "Canvas Lab $($canvasLab.Name)"
        if ($lab.LabName -eq $canvasLab.Name) {
            # Add additional properties for the Canvas LMS/LTI 
            $lab | Add-Member -MemberType NoteProperty -Name LmsInstance -Value $LMSInstance  -Force 
            $lab | Add-Member -MemberType NoteProperty -Name LtiRosterEndpoint -Value "$($LMSInstance)api/lti/courses/$($canvasLab.id)/names_and_roles"  -Force 
            $ltiUri = "$($LMSInstance)api/v1/courses/$($canvasLab.id)?include=lti_context_id"
            $ltiResult = Invoke-WebRequest -Uri $ltiUri -Method 'Get' -Headers $header -UseBasicParsing
            $ltiLab = $ltiResult.Content | ConvertFrom-Json
            $lab | Add-Member -MemberType NoteProperty -Name LtiContextId -Value $ltiLab.lti_context_id -Force
            $lab | Add-Member -MemberType NoteProperty -Name LtiClientId -Value $LTIClientId -Force
            
        }
    }
}

Write-Host "Completed running Get Canvas Lab information script, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green
return $labs
