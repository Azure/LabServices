# Lab Services

This repository contains samples extending the Azure Lab Services (post August 2022 update) experience.  

Contributions are welcome!  If there is something that you want, feel free to create an issue or pull request.

## Overview

Below are the different overarching areas. Samples are arranged by area and then technology used.

### Class Types

This area contains scripts relating to [example classes](https://learn.microsoft.com/azure/lab-services/class-types) described in the Azure Lab Services documentation.

- [Big Data Analytics](/ClassTypes/PowerShell/BigDataAnalytics/)  
- [Ethical Hacking](/ClassTypes/PowerShell/EthicalHacking/)
- [Fedora Linux](/ClassTypes/Docker/FedoraDockerContainer/)

Section also contains scripts to [enable nested virtualization](/ClassTypes/PowerShell/HyperV/), which is used by a couple example classes.

### General Scripts

These are scripts to help either tangentially to Lab Services or in support of Lab Services.

- [Creating a new VM image for Azure Compute Gallery from existing VM](/GeneralScripts/PowerShell/BringImageToSharedImageGallery/)
- [Custom Policies](/GeneralScripts/PowerShell/CustomPolicies/)

### Lab Management

This code is to help with management of labs:

- Creating labs at scale.
  - [PowerShell example](/LabManagement/PowerShell/BulkOperations/)
  - [ARM example](/LabManagement/ARM/Bulk_CreateLab_ARM.ps1)
- Customizing labs, templates, or VMs.
- Managing students, schedules, or roles at scale.

### Template Management

## Earlier Versions

If you are using the original version of Lab Services that uses lab accounts, code is in the [Azure-DevTestLab repository](https://github.com/Azure/azure-devtestlab/tree/master/samples/ClassroomLabs).

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Microsoft Open Source Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
