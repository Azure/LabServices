Setup JIT User Quota with Managed Identity

- Setup Automation account with runbook using Managed identity.
    - https://docs.microsoft.com/en-us/azure/automation/learn/powershell-runbook-managed-identity
- Setup modules
    - Add Az.LabServices.BulkOperations.psm1 as Az.LabServices.BulkOperations.zip
- Add RunBook PowerShell code
    - Copy the JITQuotaWithManagedId.ps1 into the runbook editor
- Publish
- Set schedule