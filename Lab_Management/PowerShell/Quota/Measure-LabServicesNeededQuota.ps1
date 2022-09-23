<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 

.SYNOPSIS
This script helps calculate number of cores needed when requesting more quota.

.PARAMETER -PassThru
If you would like to return the data on the pipeline, provide the -PassThru
#>

param
(
    [Parameter(Mandatory=$false, HelpMessage="To return the quota data on the pipeline, pass the 'PassThru' switch")]
    [switch] $PassThru
)

#VM Sku families, vm sizes and number of cores need for each size.
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

$neededQuotaArray = [System.Collections.ArrayList]::new()
foreach ($vmSkuFamily in $labsSizes.Values){
    $currentCores = 0
    $currentSizeName = ""

    #Get sizes for each sku family
    $currentVmSizes = $vmSkuFamily['Sizes']
    foreach ($currentVmSizeName in $currentVmSizes.Keys)
    {
        #Ask number of VMs needed for each size
        $numberOfVMs = [int](Read-Host -Prompt "How many '$($currentVmSizeName)' VMs do you need?" )

        #Calculate number of cores need for that size
        $currentCores += $numberOfVMs * $currentVmSizes[$currentVmSizeName]
        $currentSizeName += "$currentVmSizeName, "
    }
    $currentSizeName = $currentSizeName.Trim().TrimEnd(", ")
 
    #Log number of cores needed for VM Sku family
    if ($currentCores -gt 0){
        $neededQuotaArray.Add([PSCustomObject]@{
            "Sku Family" = "$($vmSkuFamily.Name)"
            "Size Names" =  $currentSizeName
            "Cores Needed" = $currentCores
        }) |Out-Null
    }
}
Write-Host ""

Write-Host "**************************" -ForegroundColor Blue
Write-Host "Notes:" -ForegroundColor Blue
Write-Host "- Additional cores quota requests are organized by the compute sku family." 
Write-Host "- To see current alloted quota for a subscription, run Get-LabServicesCapacityQuotas.ps1"
Write-Host ""
Write-Host "Results:" -ForegroundColor Blue
$neededQuotaArray | Format-Table
Write-Host "**************************" -ForegroundColor Blue

if ($PassThru) {
    # return the quota data on the pipeline 
    return $neededQuotaArray
}