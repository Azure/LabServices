Setup JIT User Quota with Managed Identity

- Setup Automation account with runbook using Managed identity.
    - https://docs.microsoft.com/azure/automation/learn/powershell-runbook-managed-identity
- Setup modules
    - Add Az.LabServices.BulkOperations.psm1 as Az.LabServices.BulkOperations.zip
- Add RunBook PowerShell code
    - Copy the JITQuotaWithManagedId.ps1 into the runbook editor
- Publish
- Set schedule
-
Setup JIT User Quota with RunAs

- Setup Automation account with runbook using RunAs.
    - https://docs.microsoft.com/azure/automation/manage-runas-account
- Setup modules
    - Add Az.LabServices.BulkOperations.psm1 as Az.LabServices.BulkOperations.zip
- Add RunBook PowerShell code
    - Copy the JITQuotaWithRunAs.ps1 into the runbook editor
- Publish
- Set schedule