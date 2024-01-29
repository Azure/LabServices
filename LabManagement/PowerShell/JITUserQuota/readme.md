
# Just-in-time User Quota

Sample that creates a just-in-time system to update a lab user's quota as needed.

## Setup with Managed Identity and Runbook

- **Setup Automation account with runbook using Managed identity**.  See [Tutorial: Create Automation PowerShell runbook using managed identity](https://docs.microsoft.com/azure/automation/learn/powershell-runbook-managed-identity) for details
- **Setup modules**.  Add Az.LabServices.BulkOperations.psm1 as Az.LabServices.BulkOperations.zip
- **Add Runbook PowerShell code**.  Copy the JITQuotaWithManagedId.ps1 into the runbook editor
- **Publish to Runbook**.  See [managing runbooks](https://learn.microsoft.com/azure/automation/manage-runbooks#publish-a-runbook) for details.
- **Set schedule**.  See [managing runbooks](https://learn.microsoft.com/azure/automation/manage-runbooks#schedule-a-runbook-in-the-azure-portal) for details.

## Setup with Managed Identity and Windows Task Scheduler
To run this script, it assumes that this repo has been cloned to the VM because it relies on the Az.LabServices.BulkOperations.psm1 script.

- **Setup Managed Identity on VM**.  The JITQuotaWithScheduledTask.psm1 script is designed to be run via Windows Task Scheduler on a dedicated Azure VM that has Managed Identity configured. See [configure managed identities](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/qs-configure-portal-windows-vm) to configure Managed Identity for the VM.
- **Setup modules**.  The script automatically installs and imports the AZ and Az.LabServicesBulkOperations.psm1 modules.
- **Setup Windows Task Scheduler**.  Use Windows Task Scheduler to schedule the script to run on regular cadence, such as the start of each week.

