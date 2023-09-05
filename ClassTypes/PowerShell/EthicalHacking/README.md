# Introduction

These scripts will guide you to create and setup an Azure Lab Services lab that is configured to run an [ethical hacking class](https://docs.microsoft.com/azure/lab-services/classroom-labs/class-type-ethical-hacking). Part 1 of these instructions will be to create the lab plan and lab resource in Azure. Part 2 of these instructions will be to prepare the template VM instance of the newly created lab to be used by your class.

- - - -

## Part 1 - Create Azure Lab Resources

This script will help create a lab plan and lab in your Azure subscription.

### Prerequisites

To create a lab using the following instructions, you must have

- Contributor permissions on the subscription in which the lab will be created

### Directions

1. Open a PowerShell window.  Make sure that the window notes it is running under *administrator* privileges.
1. Download the `Create-EthicalHackingLabplanAndLab.ps1` PowerShell script onto your **local machine**:

     ```powershell
     Invoke-WebRequest "https://raw.githubusercontent.com/Azure/LabServices/main/ClassTypes/PowerShell/EthicalHacking/Create-EthicalHackingLabplanAndLab.ps1" -OutFile Create-EthicalHackingLabplanAndLab.ps1
     ```

1. Run `Create-EthicalHackingLabplanAndLab.ps1` script.
     > [!NOTE]
     > Run `Get-help .\Create-EthicalHackingLabplanAndLab.ps1 -Detailed` to see more information about script.

     ```powershell
          Install-Module 'Az' -Force
          Login-AzAccount 
          ./Create-EthicalHackingLabplanAndLab.ps1 -UserName "AdminUser" -Password $(ConvertTo-SecureString "<password>" -AsPlainText -Force) -Location "centralus"
     ```

1. Open the [Azure Labs Services website](https://labs.azure.com) and login with your Azure credentials to see the lab created by this script.

- - - -

## Part 2 - Prepare your template virtual machine

This script will help prepare your template virtual machine for a ethical hacking class.  Script will:

- Enable Hyper-V.
- Install [7-Zip](https://www.7-zip.org/download.html) to extra Kali Linux Hyper-V disk.
- Create a Hyper-V virtual machine with a [Kali Linux](https://www.kali.org/).  Kali is a Linux distribution that includes tools for penetration testing and security auditing.
- Install [Starwind V2V Converter](https://www.starwindsoftware.com/download-starwind-products#download) to convert Metasploitable VMWare disk to Hyper-V disk.
- Create a Hyper-V virtual machine with a [Metasploitable](https://github.com/rapid7/metasploitable3) image is created.  The Rapid7 Metasploitable image is an image purposely configured with security vulnerabilities. You'll use this image to test and find issues.

### Prerequisites

- Lab with a template VM.
- Template VM for lab has a Windows Server OS.

### Directions

1. Open the [Azure Labs Services website](https://labs.azure.com) and login with your Azure credentials to see the lab created by this script.
1. [Connect to template machine](https://learn.microsoft.com/azure/lab-services/how-to-create-manage-template#update-a-template-vm) for your lab.
1. Download the `SetupForNestedVirtualization.ps1` and `Setup-EthicalHacking.ps1` and PowerShell scripts onto the **Template Virtual Machine**:

     ```powershell
     Invoke-WebRequest "https://raw.githubusercontent.com/Azure/LabServices/main/ClassTypes/PowerShell/HyperV/SetupForNestedVirtualization.ps1" -OutFile "SetupForNestedVirtualization.ps1"

     Invoke-WebRequest "https://raw.githubusercontent.com/Azure/LabServices/main/ClassTypes/PowerShell/EthicalHacking/Setup-EthicalHacking.ps1" -OutFile "Setup-EthicalHacking.ps1"
     ```

1. Open a PowerShell window.  Make sure that the window notes it is running under *administrator* privileges.
1. Run `SetupForNestedVirtualization.ps1`.  This installs the necessary features to create HyperV virtual machines.

    > [!NOTE]
    > The script may ask you to restart the machine and re-run it.  A note that the script is completed will show in the PowerShell window when no further action is needed.

1. Run `Setup-EthicalHacking.ps1`

     > [!WARNING]
     > Use `Setup-EthicalHacking.ps1 -Force` will cause any software to be installed silently.  By using the Force switch you are automatically accepting the terms for the installed software.  
