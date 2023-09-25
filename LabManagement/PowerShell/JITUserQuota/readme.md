
# Just-in-time User Quota

Sample that creates a just-in-time system to update a lab user's quota as needed.

## Setup with Managed Identity

- **Setup Automation account with runbook using Managed identity**.  See [Tutorial: Create Automation PowerShell runbook using managed identity](https://docs.microsoft.com/azure/automation/learn/powershell-runbook-managed-identity) for details
- **Setup modules**.  Add Az.LabServices.BulkOperations.psm1 as Az.LabServices.BulkOperations.zip
- **Add Runbook PowerShell code**.  Copy the JITQuotaWithManagedId.ps1 into the runbook editor
- **Publish to Runbook**.  See [managing runbooks](https://learn.microsoft.com/azure/automation/manage-runbooks#publish-a-runbook) for details.
- **Set schedule**.  See [managing runbooks](https://learn.microsoft.com/azure/automation/manage-runbooks#schedule-a-runbook-in-the-azure-portal) for details.

## Setup with RunAs

- **Setup Automation account with runbook using RunAs**. See [Manage an Azure Automation Run As account](https://docs.microsoft.com/azure/automation/manage-runas-account) for details.
- **Setup modules**.  Add Az.LabServices.BulkOperations.psm1 as Az.LabServices.BulkOperations.zip
- **Add RunBook PowerShell code**. Copy the JITQuotaWithRunAs.ps1 into the runbook editor
- **Publish to Runbook**.  See [managing runbooks](https://learn.microsoft.com/azure/automation/manage-runbooks#publish-a-runbook) for details.
- **Set schedule**.  See [managing runbooks](https://learn.microsoft.com/azure/automation/manage-runbooks#schedule-a-runbook-in-the-azure-portal) for details.
