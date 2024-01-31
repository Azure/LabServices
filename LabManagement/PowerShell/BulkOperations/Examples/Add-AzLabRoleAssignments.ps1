[CmdletBinding()]
param(
    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string]
    $CsvConfigFile,
 
    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string]
    $RoleDefinitionName
)
 
Set-StrictMode -Version Latest
Import-Module -Name Az.Resources -Force
 
# Make sure the input file does exist
if (-not (Test-Path -Path $CsvConfigFile)) {
    Write-Error "Input CSV File must exist, please choose a valid file location..."
}
 
$scriptstartTime = Get-Date
Write-Host "Executing bulk teacher permission add script, starting at $scriptstartTime" -ForegroundColor Green
 
# Import the CSV file (plain import not using the library)
$labs = Import-Csv -Path $CsvConfigFile
 
# Loop through the labs to apply role assignments
foreach ($lab in $labs) {
 
    # continue only if we have 'Teachers' column and it has data
    if ($lab.PSObject.Properties['Teachers'] -and $lab.Teachers)
    {
        # Get the lab
        $labObj = Get-AzResource -ResourceGroupName $lab.ResourceGroupName -Name $lab.LabName
 
        $lab.Teachers.Split(";") | ForEach-Object {
            # make sure we didn't accidently have an extra semicolon with empty data
            if ($_) {
 
                $roleAssignment = Get-AzRoleAssignment -SignInName $_ -Scope $labObj.ResourceId -RoleDefinitionName $RoleDefinitionName -ErrorAction SilentlyContinue
                if ($roleAssignment) {
                    Write-Host "Role assignment for teacher $_ already exists in lab $($lab.LabName) in Resource Group Name $($lab.ResourceGroupName)" -ForegroundColor Yellow
                }
                else {
                    Write-Host "Adding role assignment for teacher $_ in lab $($lab.LabName) in Resource Group Name $($lab.ResourceGroupName)"
                    New-AzRoleAssignment -SignInName $_ -RoleDefinitionName $RoleDefinitionName -Scope $labObj.ResourceId | Out-Null
                }
            }
        }
    }
}
 
Write-Host "Completed bulk teacher permission add script, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green