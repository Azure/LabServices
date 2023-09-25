# Introduction

This script is used to calculate how many cores are needed in each family for the Lab Services virtual machine sizes.  This is commonly used when requesting additional quota for Azure Lab Services.  The results can be saved to a CSV file along with displayed to the console.

## Prerequisites

- [Azure PowerShell module](https://docs.microsoft.com/powershell/azure)
- [Azure Lab Services PowerShell module](https://www.powershellgallery.com/packages/Az.LabServices)

## Directions

1. Open a PowerShell window.
2. Run `Measure-LabServicesNeededQuota.ps1` .  If you would like to return the results on the pipeline, please use the "PassThru" parameter.

``` Powershell
    # Calculate the cores needed for a Lab Services Virtual Machine Size:
    Measure-LabServicesNeededQuota.ps1

    # Calculate the cores needed and write the results to a CSV file
    Measure-LabServicesNeededQuota.ps1 -PassThru | Export-Csv -Path .\CoresNeeded.csv -NoTypeInformation

```

For related information, refer to the following articles:

- [About Azure Lab Services](https://docs.microsoft.com/azure/lab-services/lab-services-overview)
- [Capacity Limits in Azure Lab Services](https://docs.microsoft.com/azure/lab-services/capacity-limits)
- [Reference Guide for Azure Lab Services Powershell Module](https://docs.microsoft.com/powershell/module/az.labservices)
