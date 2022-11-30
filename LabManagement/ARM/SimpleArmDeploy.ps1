[CmdletBinding()]
param(
    
[parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
[ValidateNotNullOrEmpty()]
[string] $LabPlanName,

[parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
[ValidateNotNullOrEmpty()]
[string] $LabName,

[parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
[ValidateNotNullOrEmpty()]
[string] $ResourceGroupName,

[parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
[ValidateNotNullOrEmpty()]
[string] $Location,

[parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
[ValidateNotNullOrEmpty()]
[string] $AdminName,

[parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
[ValidateNotNullOrEmpty()]
[string] $AdminPassword,


[parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
[ValidateNotNullOrEmpty()]
[string] $ARMFile

)
    

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hashParameters = @{LabName = $LabName; LabPlanName = $LabPlanName; Location = $Location; AdminUser = $AdminName; AdminPassword = $AdminPassword}
New-AzResourceGroupDeployment -Name "TestDeploy" -AsJob -ResourceGroupName $ResourceGroupName -TemplateFile $ARMFile -TemplateParameterObject $hashParameters

Get-Job | Wait-Job

