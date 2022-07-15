# Introduction
This script is used to check the Azure Lab Services quotas across all regions for a specific subscription.  The results can be saved to a CSV file along with displayed to the console.

## Prerequisites
- [Azure PowerShell module](https://docs.microsoft.com/powershell/azure)
- [Azure Lab Services PowerShell module](https://www.powershellgallery.com/packages/Az.LabServices)

# Directions
1. Open a PowerShell window.
2. Run `Get-LabServicesCapacityQuotas.ps1` .  If you would like to save the quota details to a CSV file, please use the "OutputCSV" parameter and specify a filename.

``` Powershell
    # Display the details on Quotas to the console
    Get-LabServicesCapacityQuotas.ps1

    # Display the Quotas and output the full data to a CSV file
    .\Get-LabServicesCapacityQuotas.ps1 -PassThru | Export-Csv -Path .\quotas.csv -NoTypeInformation

```

For related information, refer to the following articles:
- [About Azure Lab Services](https://docs.microsoft.com/en-us/azure/lab-services/lab-services-overview)
- [Capacity Limits in Azure Lab Services](https://docs.microsoft.com/en-us/azure/lab-services/capacity-limits)
- [Reference Guide for Azure Lab Services Powershell Module](https://docs.microsoft.com/en-us/powershell/module/az.labservices)
