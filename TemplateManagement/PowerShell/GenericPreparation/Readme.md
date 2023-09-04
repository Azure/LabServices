# Azure Lab Services VM preparation

This folder contains scripts useful for setting up an Azure Lab Services VM for the first time. They are fully described in the [How to prepare a windows template](https://docs.microsoft.com/azure/lab-services/classroom-labs/how-to-prepare-windows-template) article.

1. **Prepare-Updates.ps1**. This script installs updates for a Windows client machine and turns off automatic updates to avoid class disruption.
2. **Prepare-OneDrive**. This script prepares a the OneDrive install for a Windows client machine for a generic class.
3. **Prepare-MicrosoftStoreApplications.ps1**. This script prepares a computer for class by aiding in the deletion of unneeded Microsoft Store applications. The remaining Microsoft Store applications are updated.
