<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 

.SYNOPSIS
This script checks all the quotas for Lab Services across all regions

.PARAMETER -PassThru
If you would like to return the data on the pipeline, provide the -PassThru
#>

param
(
    [Parameter(Mandatory=$false, HelpMessage="To return the quota data on the pipeline, pass the 'PassThru' switch")]
    [switch] $PassThru
)

$subscriptionId = (Get-AzContext).Subscription.Id

$labsSizes = [Ordered]@{
    Fsv2 = @{
        Name = "CPU Cores (Fsv2)"
        Sizes = [Ordered]@{
            "Small" = 2
            "Medium" = 4
            "Large" = 8
            }
        }
    Dsv4 = @{
        Name = "CPU Virtualization Cores (Dsv4)"
        Sizes = [Ordered]@{
            "Medium (Nested Virtualization)" = 4
            "Large (Nested Virtualization)" = 8
            }
        }
    NCv3T4 = @{
        Name = "GPU Compute (NCv3T4)"
        Sizes = [Ordered]@{
            "Small GPU (Compute)" = 6
            }
        }
    NVv4 = @{
        Name = "GPU Visualization (NVv4)"
        Sizes = [Ordered]@{
            "Small GPU (Visualization)" = 8
            "Medium GPU (Visualization)" = 12
            }
        }
}

$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $((Get-AzAccessToken).Token)
}

# Let's figure out all regions where Lab Services is used:
$restUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/microsoft.labservices?api-version=2014-04-01-preview"
$response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader

# List of all regions available for lab services
$availableRegionsForLabs = ($response.resourceTypes | Where-Object {$_.resourceType -ieq "labplans"}).Locations

# Save a table of region short names to display names
$locations = Get-AzLocation

$quotas = $availableRegionsForLabs | ForEach-Object {
    $regionDisplayName = $_
    # Get the short code for the region:
    $region = ($locations | Where-Object {$_.DisplayName -ieq $regionDisplayName} | Select-Object -First 1).Location
    
    $authHeader = @{
        'Content-Type'='application/json'
        'Authorization'='Bearer ' + $((Get-AzAccessToken).Token)
    }

    $restUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.LabServices/locations/$region/usages?api-version=2021-11-15-preview"
    try {
        $response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader

        $response.value | Where-Object {$_.limit -gt 0} |
                Select-Object -Property `
                    @{Name = 'Region'; Expression = {$region}},
                    @{Name = 'RegionName'; Expression = {$regionDisplayName}},
                    @{Name = 'Size'; Expression = {$_.name.value}},
                    @{Name = "LabSize"; Expression = {$labsSizes[$_.name.value].Name}},
                    @{Name = 'UsedCores'; Expression = {$_.currentValue}},
                    @{Name = 'TotalCores'; Expression = {$_.limit}},
                    @{Name = 'PercentUsed'; Expression = {[Math]::Round($_.currentValue / $_.limit * 100)}},
                    @{Name = 'AvailableVMs'; Expression = {
                            $availableCores = $_.limit - $_.currentValue
                            ($labsSizes[$_.name.value].Sizes.GetEnumerator() | ForEach-Object {
                                "$([Math]::Floor($availableCores / $_.Value)) $($_.Name)"
                            }) -join ' | ' }}
                            
    }
    catch [System.Net.WebException] {
        # There are a few regions where labs isn't deployed, so we get errors for those that we can ignore
    }
}

$groups = $quotas | Group-Object -Property LabSize | 
    Where-Object {$_.Name -and $_.Name -ine "labPlans" -and $_.Name -ine "labs"}  # There are some sizes we have quotas for like Esv2 that aren't mapped

foreach ($group in $groups) {
    Write-Host "Type of Cores:  $($group.Name)" -ForegroundColor Cyan
    $group.Group | 
        Select-Object -Property RegionName, UsedCores, TotalCores, PercentUsed, AvailableVMs | 
        Format-Table -AutoSize | Out-String | Write-Host
}

Write-Host "More information about sizes can be found here:" -ForegroundColor Green
Write-Host "https://docs.microsoft.com/en-us/azure/lab-services/administrator-guide" -ForegroundColor Green

if ($PassThru) {
    # return the quota data on the pipeline 
    return $quotas
}
