# Lab Services ARM support
> THIS SECTION IS UNDER ACTIVE DEVELOPMENT, SCRIPTS AND TEMPLATES MAY NOT BE FULLY FUNCTIONAL

## Simple ARM example.
This section contains a simple lab creation using an ARM template with a PowerShell script to execute the Resource Group deployment.
- LabTemplate_Simple_.json
    - This ARM template has only five input parameters (LabName, LabPlanName, Location, AdminUser, AdminPassword) the rest of the options are hardcoded into the template.
- SimpleArmDeploy.ps1
    - Passes the parameters into the ResourceGroupDeployment.

## Bulk deployment using ARM template.

Use a CSV file to create multiple labs asynchronously
- BellowsCollegeLabs_Sample.csv
    - Lab to be created CSV sample.
- BC_CompSci_AI_200_Schedule_Sample.csv
    - Schedules for the labs sample.
- Bulk_CreateLab_ARM.ps1
    - Create Labs, Add Users, add schedules
- Bulk_AddSchedules.ps1
    - Add schedules
- Bulk_AddUsers.ps1
    - Add users
- Bulk_Publish.ps1
    - Publish all labs in the CSV
- Bulk_RemoveLabs.ps1
    - Remove all labs in the CSV
