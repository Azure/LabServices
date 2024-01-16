# Bulk Lab Creation Module <!-- omit in toc -->
The [Az.LabServices.BulkOperations.psm1](https://github.com/Azure/LabServices/Lab_Management/PowerShell/BulkOperations/Az.LabServices.BulkOperations.psm1) module enables bulk operations on **Resource Groups**, **Lab Plans** and **Labs** via commandline based on declarative configuration information. The standard pattern of usage is by composing a pipeline as follows:

`Load configuration info from db/csv/...` => `Transform configuration info` => `Publish the labs`

## Table of Contents
- [Table of Contents](#table-of-contents)
- [Getting Started](#getting-started)
- [Examples](#examples)
  - [Publish all the labs in a CSV file (Examples/PublishAll.ps1)](#publish-all-the-labs-in-a-csv-file-examplespublishallps1)
  - [Show a menu asking to select one lab (Examples/PickALab.ps1)](#show-a-menu-asking-to-select-one-lab-examplespickalabps1)
- [Structure of the example BellowsCollegeLabs_Sample.csv](#structure-of-the-example-bellowscollegelabs_samplecsv)
- [Structure of the example BC_CompSci_AI_200_Schedule_Sample.csv](#structure-of-the-example-bc_compsci_ai_200_schedule_sample.csv)

## Getting Started
The [Bulk Lab Creation functions](./Examples) can be run from an authenticated Azure PowerShell session and requires [PowerShell](https://github.com/PowerShell/PowerShell/releases) and the [Azure PowerShell](https://docs.microsoft.com/en-us/powershell/azure/) module.  The script will automatically install the [ThreadJob](https://docs.microsoft.com/en-us/powershell/module/threadjob) Powershell Module.

To get started, using the example configuration csv files:

1. Get a local copy of the Bulk Operations scripts by either [cloning the repo](https://github.com/Azure/LabServices.git) or by [downloading a copy](https://raw.githubusercontent.com/Azure/LabServices/main/Lab_Management/PowerShell/BulkOperations/Az.LabServices.BulkOperations.psm1)
1. Get a local copy of the example [BellowsCollegeLabs_Sample.csv](./Examples/BellowsCollegeLabs_Sample.csv) file and example [BC_CompSci_AI_200_Schedule_Sample.csv](./Examples/BC_CompSci_AI_200_Schedule_Sample.csv) file
1. Launch a PowerShell session
1. Ensure [Azure PowerShell](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps) installed
1. Update the example CSV files to configure the resources to be created.  For additional labs, create additional lines in the CSV file.  The CSV files can be modified directly with Microsoft Excel.

## Examples
The functions are generic and can be composed together to achieve different aims. In the following examples, we load the configuration information from a CSV file. The examples work the same if the information is loaded from a database. You need to substitute the first function with a database retrieving one.

The examples scripts expect the modules used to be in the following directories:

```powershell
Import-Module ../Az.LabServices.BulkOperations.psm1 -Force
```

The full code for the example is immediately after the title in parenthesis.

### Publish all the labs in a CSV file ([Examples/PublishAll.ps1](./Examples/PublishAll.ps1))

```powershell
".\BellowsCollegeLabs_Sample.csv" | Import-LabsCsv | Publish-Labs
```
* `Import-LabsCsv` loads the configuration information from the csv file. It also loads schedule information for each lab from a separate file.
* `Publish-Labs` publishes the labs and it is the natural end to all our pipelines. You can specify how many concurrent threads to use with the parameter `ThrottleLimit`.

### Show a menu asking to select one lab ([Examples/PickALab.ps1](./Examples/PickALab.ps1))

```console
".\hogwarts.csv" | Import-LabsCsv | Show-LabMenu -PickLab | Publish-Labs

LABS
[0]     id001   hogwarts-rg2    History of Magic
[1]     id002   hogwarts-rg2    Transfiguration
[2]     id003   hogwarts-rg2    Charms
Please select the lab to create:
```

* The fields displayed for the various labs are fixed. Log an issue if you want me to make them configurable.


## Structure of the example [BellowsCollegeLabs_Sample.csv](./Examples/BellowsCollegeLabs_Sample.csv)
Item              | Description
----------------- | -------------
Id                | A unique id for the lab
Tags              | A set of tags applied to the lab.
ResourceGroupName | The name of the resource group that the lab plan will be created in.  If the resource group doesn't already exist, it will be created.
Location          | The region that the Lab will be created in, if the lab doesn't already exist.  If the Lab in the Lab Plan's resource group already exists, this row is skipped.
LabPlanName       | The name of the Lab Plan to be created, if the lab plan doesn't already exist or if different will be adjusted to the defaults.  If your lab plan needs advanced networking, we recommend that you manually create your lab plan and only use this script for deploying labs.
LabName           | The name of the Lab to be created.
ImageName         | The image name that the lab will be based on.  Wildcards are accepted, but the ImageName field should match only 1 image.
AadGroupId        | The AadGroupId, used to connect the lab for syncing users.  Used to enable Microsoft Teams support for this lab.
MaxUsers          | Maximum number of users expected for the lab.
UsageQuota        | Maximum quota per student.
UsageMode         | Type of usage expected for the lab.  Either "Restricted" - only those who are registered in the lab, or "Open" anyone.
SharedPassword    | Enabled\Disabled values indicate whether the lab should use a shared password.  "Enabled" means the lab uses a single shared password for the student's virtual machines, "Disabled" means the students will be prompted to change their password on first login.
Size              | The Virtual Machine size to use for the Lab. Please see details below on how these map to the Azure Portal.
Title             | The title for the lab.
Descr             | The description for the lab.
UserName          | The default username for admin account.
Password          | The default password for admin account.
NonAdminUserName  | Username for optional non-admin account.
NonAdminPassword  | Password for optional non-admin account.
LinuxRdp          | Set to "True" if the Virtual Machine requires Linux RDP, otherwise "False".
Emails            | Semicolon separated string of student emails to be added to the lab.  For example:  "bob@test.com;charlie@test.com"
LabOwnerEmails    | Semicolon separated string of teacher emails to be added to the lab.  The teacher will get Owner rights to the lab, and Reader rights to the Lab Account.  NOTE: this account must exist in Azure Active Directory tenant.
Invitation        | Note to include in the invitation email to students.  If you leave this field blank, invitation emails won't be sent during lab creation.
Schedules         | The name of the csv file that contains the schedule for this class.  For example: "charms.csv".  If left blank, a schedule won't be applied.
TemplateVmState   | Enabled\Disabled values indicate whether the lab should have a template VM created.
IdleGracePeriod   | Number of minutes between 15-59 to shut down lab VMs after idle state is detected.
IdleOsGracePeriod | Number of minutes between 15-59 to disconnect lab VMs after a user disconnects.
IdleNoConnectGracePeriod | Number of minutes between 15-59 to shut down lab VMs when a user doesn't connect.

## Structure of the example [BC_CompSci_AI_200_Schedule_Sample.csv](./Examples/BC_CompSci_AI_200_Schedule_Sample.csv)
Item              | Description
----------------- | -------------
Frequency         | How often, "Weekly" or "Once"
FromDate          | Start Date
ToDate            | End Date
StartTime         | Start Time
EndTime           | End Time
WeekDays          | Days of the week.  "Monday, Tuesday, Friday".  The days are comma separated with the text. If Frequency is "Once" use an empty string "" 
TimeZoneId        | Time zone for the classes.  "Central Standard Time"
Notes             | Additional notes

## Virtual Machine Sizes
There are three categories of VM sizes that you can use: **Default VM sizes**, **Alternative VM sizes**, and **Classic VM sizes**.   More information can be found in the [Lab Services Admin Guide](https://docs.microsoft.com/azure/lab-services/administrator-guide#vm-sizing).

When you use the bulk deployment script to create labs, you must specify either the VM SKU Name or VM SKU Size that is expected by the underlying API.  If you specify the friendly name shown in the portal, you will get an error.

For the **Default VM sizes**, the following table shows the mapping between the friendly name shown in the portal and the underlying VM SKU Name/Size expected by the API.

Friendly Name (shown in portal)| Underlying VM SKU Name | Underlying VM SKU Size           
-------------------------------|---------------------------------------------------------
Small                          | Basic                  | Fsv2_2_4GB_128_S_SSD
Medium                         | Standard               | Fsv2_4_8GB_128_S_SSD
Medium (nested virtualization) | Virtualization         | Dsv4_4_16GB_128_P_SSD
Large                          | Large                  | Fsv2_8_16GB_128_S_SSD
Large (nested virtualization)  | Performance            | Dsv4_8_32GB_128_P_SSD
Small GPU (visualization)      | SmallGPUVisualization  | NVv4_8_28GB_128_S_SSD  
Small GPU (Compute)            | SmallGPUCompute        | Ncv3t4_8_56GB_128_S_SSD
Medium GPU (visualization)     | MediumGPUVisualization | NVv3_12_112GB_128_S_SSD

For the **Alternative VM sizes**, it's easiest to specify the underlying VM SKU Size.  The following table shows the mapping between the friendly name in the portal and the underlying VM SKU Size expected by the API.

Friendly Name (shown in portal)   | Underlying VM SKU Size
----------------------------------|---------------------------------------
Alt. Small GPU (compute)          | NCsv3_6_112GB_128_S_SSD
Alt. Small GPU (visualization)    | NVadsA10v5_6_55GB_128_S_SSD
Alt. Medium GPU (visualization)   | NVadsA10v5_12_110GB_128_S_SSD

Likewise, for the **Classic VM sizes**, it's easiest to specify the underlying VM SKU Size.  The following table shows the mapping between the friendly name in the portal and the underlying VM SKU Size expected by the API.

Friendly Name (shown in portal)   | Underlying VM SKU Size
----------------------------------|---------------------------------------
Classic Small                     | Av2_2_4GB_128_S_SSD   
Classic Medium                    | Av2_4_8GB_128_S_SSD 
Classic Large                     | Av2_8_16GB_128_S_SSD  
Classic Medium (nested virt.)     | Dsv3_4_16GB_128_P_SSD
Classic Large (nested virt.)      | Dsv3_8_32GB_128_P_SSD
Classic Small GPU (compute)       | NC_6_56GB_128_S_SSD
Classic Small GPU (visualization) | NV_6_56GB_128_S_SSD
Classic Medium GPU (visualization)| NVv3_12_112GB_128_S_SSD

## Troubleshooting
To get more detailed logging to debug issues, we recommend that you follow the steps in this article: [Enable debug logging](https://learn.microsoft.com/powershell/azure/troubleshooting?view=azps-11.1.0#enable-debug-logging).  Remember to use -Verbose flag when calling the module to see the verbose messages.