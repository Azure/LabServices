[CmdletBinding()]
param(
    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string]
    $PolicyName,

    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string]
    $PolicyScope
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptstartTime = Get-Date
Write-Host "Removing Policy $PolicyName with Scope $PolicyScope, starting at $scriptstartTime" -ForegroundColor Green

Remove-AzPolicyAssignment -Name $PolicyName -Scope $PolicyScope

Write-Host "Complete policy removal, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green