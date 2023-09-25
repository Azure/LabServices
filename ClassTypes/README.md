# Class Type Scripts

This folder contains scripts that aid in the setup of example classes explained in [Azure Lab Services Class Types](https://learn.microsoft.com/azure/lab-services/class-types).

| Class Type Name | Description |
|-----------------|-------------|
| [BigDataAnalytics](./PowerShell/BigDataAnalytics/) |  Provides students with an easy-to-use experience for a big data analytics class that uses [Hortonworks Data Platform's](https://www.cloudera.com/products/hdp.html) (HDP) Docker deployment.|
| [FedoraDockerContainer](./Bash/FedoraDockerContainer/) | Walks through the high-level steps for configuring a lab that runs a Fedora Docker container on the student’s lab VM |
| [EthicalHacking](./PowerShell/EthicalHacking/) | Creates lab that is configured to run an [ethical hacking class](https://docs.microsoft.com/azure/lab-services/classroom-labs/class-type-ethical-hacking). |
| [HyperV](./PowerShell/HyperV/) | Prepares a template virtual machine for a classroom lab to use Hyper-V [nested virtualization](https://learn.microsoft.com/azure/lab-services/concept-nested-virtualization-template-vm).  Nested virtualization is required for the [Ethical Hacking](./PowerShell/EthicalHacking/) and [Networking with GNS3](https://learn.microsoft.com/azure/lab-services/class-types#networking-with-gns3) class types. |
