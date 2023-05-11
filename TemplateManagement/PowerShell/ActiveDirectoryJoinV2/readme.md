# Sample: Domain register or join Windows 10/11 lab VMs
This sample provides scripts to help with two recommended options for registering/joining Azure Lab Services VMs to a domain:
- **Students self-register/join**: Students can self-register (via [AAD register](https://learn.microsoft.com/azure/active-directory/devices/concept-azure-ad-register)) or self-join (via [AAD join](https://learn.microsoft.com/azure/active-directory/devices/concept-azure-ad-join-hybrid)) their lab VMs.  Even when students self-register/join their lab VMs, you need to rename the lab VMs to ensure they are unique before they are registerd/joined to AAD by students.  We provide [sample PowerShell scripts](#rename-student-vms-for-aad-register-and-aad-join) that rename student VMs to unique names.
- **Domain join on behalf of students**: IT admins can domain join lab VMs on behalf of students using PowerShell to Hybrid AAD join.  We provide [sample PowerShell scripts](#hybrid-aad-join-vms-on-behalf-of-students) that perform the domain join.

For more information on this sample, see the blog post **TODO - need to add link when published**.

## Rename VMs for student self-register/join to AAD
Before a student can self-register/join their lab VM to AAD, the lab VM names should be both unique and meaningful to make it easier to manage them in AAD.  By default, Azure Labs doesn’t uniquely name lab VMs.  For example, if you enable the **Create a template virtual machine** option when you create the lab, the lab VMs will all be named like “lab000001”.  Or, if you leave this option disabled so that no template VM is created, the lab VMs will be named uniquely within a lab, but _not_ across labs.

The steps in this section show how to set up the sample scripts that uniquely rename lab VMs.  For the full set of steps that show how students can self-register/join their lab VMs to AAD, see the blog post **TODO - need to add link when published**.

### Prerequisites
- **Lab creation**: The lab must be created with the **Create a template virtual machine** option enabled.  If you are planning students to AAD join their lab VMs, you should also enable the **Use same password for all virtual machines** option.
- **Template VM setup**: You should install all other software/customizations *before* you set up the scripts to rename.  Also, we *don't* recommend exporting the template VM image with the scripts set up because they may cause ill-side effects (e.g., script inadvertently run on startup, errorneous values saved in the SecretStore, etc.)
- **Windows versions**: The template and student VMs should use a Windows 10/11 image.

The steps in this sample typically need to be performed by an **IT admin** or **educator** who has:
- Permission to [create labs](https://learn.microsoft.com/azure/lab-services/concept-lab-services-role-based-access-control#lab-creator-role) (at a minimum) in Azure Lab Services.
- Proficiency with scripting, such as PowerShell.

### Information you'll need
- Lab name prefix. The VMs need unique names and the prefix will help identify the lab that the VMs belong to when viewing device entries in AD/AAD.
- A SecretStore password.  This should be the password of a secondary local admin account that you add to the template VM, that is used to store values in the SecretStore.  You _shouldn't_ use the default local admin account because students that AAD join their lab VMs will need to use this account the first time they log into their lab VM.  Likewise, you may want students that use AAD register to also use the default local admin account.  For more info see the [Increasing security](#increasing-security) section.

### Template VM details
1.  Start the template VM and connect using the secondary local admin account.
1.  Download the **Set-RenameValuesToSecretStoreTemplate.ps1** script.
1.  Run the **Set-RenameValuesToSecretStoreTemplate.ps1** as an administrator.
1.  Fill in the requested information.
    - SecretStore password
    - Lab prefix
1. Use Windows Task Scheduler to schedule the **Rename-StudentVM.ps1** script to automatically run on startup. This will trigger the **Rename-StudentVM.ps1** script to run on the student VMs when they are started.  The task should be scheduled to run under the secondary local admin account. Otherwise, if you don't use Task Scheduler, you can instead connect to each student VM using the secondary local admin account and manually run the **Rename-StudentVM.ps1** script.

The **Set-RenameValuesToSecretStoreTemplate.ps1** script does several actions:
- Creates a SecretStore with an encrypted password file.
- Adds secrets to the SecretStore.
- Downloads the **Rename-StudentVM.ps1** script that will be run on the student vm.

On the template VM, the script will create a SecretStore that is specific to the current logged in user with the password entered.  The password is stored in an encrypted file specific to the user.  Additional secrets are added to the SecretStore to be accessed by the **Rename-StudentVM.ps1** script.

### Publish and start all student VMs
After you're done setting up the template VM:
1.  Publish the lab.
1.  Start all the student VMs which will trigger the **Rename-StudentVM.ps1** script to run on each student VM.  

Once the student VMs are renamed:
- If the student is AAD joining their VM, they should log in the first time using the local admin account and follow the steps in the TODO: Link to blog post.  Once their lab VM is AAD joined, they can log in with their domain account by changing the RDP connection file accordingly.
- If the student is AAD registering their VM, they can log in using either a local admin or non-admin accounnt and follow the steps in the TODO: Link to blog post.  Once their lab VM is AAD registered, they will continue to use the local admin or non-admin account to log in.

The **Rename-StudentVM.ps1** does several actions:
- Renames the student VM using the lab prefix and a random number.  Unique VM names are required to domain join.
- Removes the encrypted password file.
- Restarts the VM.

## Hybrid AAD join VMs on behalf of students
This sample shows how to Hybrid AAD join Azure Lab Services student VMs.  Once the student VMs are domain joined, they can log in to their lab VM with their domain account using the RDP client.

### Prerequisites
- **Line-of-site to domain controller**: The lab must have network line-of-site to your on-prem domain controller by using [advanced networking](https://learn.microsoft.com/azure/lab-services/how-to-connect-vnet-injection). 
- **Azure Active Directory (AAD) group**: This sample assumes that an [AAD group](https://learn.microsoft.com/azure/lab-services/how-to-configure-student-usage#add-users-to-a-lab-from-an-azure-ad-group) is used to manage students registered for the lab.  The Join-Domain-StudentVM.ps1 script adds the students from the AAD group to Remote Desktop Users on each domain joined student VM to enable RDP connection.
- **Lab creation**: The lab must be created with **Use same password for all virtual machine** enabled and **Create a template virtual machine** enabled; the lab should be set up to sync students from the AAD group mentioned in the previous bullet.
- **Template VM setup**: You should install all other software/customizations *before* you set up the scripts to domain join.  Also, we *don't* recommend exporting the template VM image with the scripts set up because they may cause ill-side effects (e.g., script inadvertently run on startup, errorneous values saved in the SecretStore, etc.)
- **Windows versions**: The template and student VMs should use a Windows 10/11 image.

The steps in this sample typically need to be performed by an **IT admin** who has:
- Permission to domain join and manage devices in AD/AAD.
- Permission to [create labs](https://learn.microsoft.com/azure/lab-services/concept-lab-services-role-based-access-control#lab-creator-role) (at a minimum) in Azure Lab Services.
- Proficiency with scripting, such as PowerShell.

**NOTE**: When you set up line-of-site to your domain controller, you shouldn’t change the DNS settings at the OS level on your lab VMs to point to your domain controller’s IP – this can cause ill side effects, such as losing RDP connection to your lab VMs.  Instead, you should change the DNS settings on the lab’s VNet.  

### Information you'll need
- User name and password of an account that has permission to join the VM to the domain.
- Name of the domain to join.
- Lab name prefix. The VMs need unique names and the prefix will help identify the lab that the VMs belong to when viewing device entries in AD/AAD.
- A secret store password.  This password should be different than the VM's local account password and the password of the account that has permission to domain join.
- AAD group name that is used to manage students registered for the lab.

### Set up the template VM
1.  Start the template VM and connect using the default local admin account.
1.  Before setting up the scripts to domain join, make sure that the template VM has configuration changes and software installed that are needed for the lab.
1.  Download the **Set-DomainJoinValuesToSecretStore-TemplateVM.ps1** script.
1.  Run the **Set-DomainJoinValuesToSecretStore-TemplateVM.ps1** as an administrator.
1.  Fill in the requested information.
    - SecretStore password
    - Domain join user name
    - Domain join user password
    - AAD group name
    - Lab prefix
    - Current user password
1.  Use Windows Task Scheduler to schedule the **Join-Domain-Student.ps1** script to automatically run on startup.  This will trigger the **Join-Domain-Student.ps1** script to run on the student VMs when they are started.  Otherwise, if you don't use  Task Scheduler, you can instead manually connect to each student VM and run the **Join-Domain-Student.ps1** script.
    
The **Set-DomainJoinValuesToSecretStore-TemplateVM.ps1** script does several actions:
- Creates a SecretStore with and encrypted password file.
- Adds secrets to the SecretStore.
- Downloads the **Join-Domain-Student.ps1** script that will be run on the student VM.

On the template VM, the script will create a SecretStore that is specific to the current logged in user with the password entered.  The password is stored in an encrypted file specific to the user.  Additional secrets are added to the SecretStore to be accessed by the **Join-Domain-Student.ps1** script.  This script is downloaded from the repository and stored in the public documents folder.

### Publish and start all student VMs
After you're done setting up the template VM:
1.  Publish the lab.
1.  Start all the student VMs which will trigger the **Join-Domain-Student.ps1** script to run on each student VM.  
1.  Confirm that each VM successfully joined to the domain; for example, check for the corresponding device entry in AD/AAD.

Once the student VMs are Hybrid AAD joined, they can log in with their domain account using the RDP client.  Students will need to remember to change the RDP connection file to use their domain account instead of the default local account.

The **Join-Domain-Student.ps1** script does several actions:
- Renames the student VM using the lab prefix and a random number.  Unique VM names are required to domain join.
- Adds the computer to the domain.
- Adds the AAD group to the Remote Desktop Users group.
- Removes the encrypted password file.
- Removes the **Join-Domain-Student.ps1** script
- Restarts the VM.

# Known caveats
## Publishing and resetting lab VMs
When you rename or domain register/join your lab VMs, we recommend that you avoid republishing or resetting VMs.  Each time you republish or reset a lab VM, the student VMs are reimaged and are _no_ longer uniquely named or domain joined.  As a result, students will _no_ longer be able to connect to their VM using their domain account.

**AAD register/join**: When a student resets their VM, the **Rename-StudentVM.ps1** script will need to be rerun before they re-register/re-join their VM.  If you scheduled a startup task to run the **Rename-StudentVM** script, the script will be automatically run the first time the new VM is started. 

**Hybrid AAD join**: When a student resets their VM, the **Join-Domain-StudentVM.ps1** script will need to be rerun before they can log in with their domain account.  If you scheduled a startup task to run the **Join-Domain-StudentVM.ps1** script, the script will be automatically run the first time the new VM is started.  You should ensure that the new VMs are started and successfully joined to the domain before students try to log in again with their domain account.

Similar steps should also be followed if a lab is republished.

## Increasing VM pool capacity
Whenever you increase the VM pool capacity after you have renamed or domain registered/joined your lab VMs, the new VMs will need to also be renamed and domain registered/joined.

**AD register/join**:  The **Rename-StudentVM.ps1** script will need to be rerun before they re-register/re-join their VM.  If you scheduled a startup task to run the **Rename-StudentVM** script, the script will be automatically run the first time the new VM is started. 

**Hybrid AAD join**: The **Join-Domain-StudentVM.ps1** script will need to be run on the new machines before students can access them with their domain account.  If you scheduled a startup task to run the **Join-Domain-StudentVM.ps1** script, the script will be automatically run the first time the new VM is started.  After the script runs, you should confirm that the VM joined successfully to the domain.  Since this sample uses an AAD group to manage students, the VM pool capacity is automatically synced based on the AAD group's student membership - this means a lab VM is automatically added/deleted whenever a student is added/deleted from the AAD group.

## Managing the template VM
The template VM shouldn’t be joined to a domain because this image is used to create the student VMs and can be exported to create other labs.  You _can't_ reuse an image from a device that is already Hybrid AAD joined.  Instead, only the student VMs should be joined to a domain.  

The **Join-Domain-StudentVM.ps1** script explicitly checks if it's being run on a student VM before it attempts to join to the domain.

# Troubleshooting
- The log file for the script is located in the logged in account's user folder.  The file will prefaced with "DJLog" followed by the date and time that the file was created.  All error messages will be logged there.

- If you are having issues with the script failing when run from a scheduled task, disable the task and try running the script manually from the student VM.  

- Check that the student VM is properly joined to the domain.
    - View the proper domain name in the AD/AAD UI.
    - Open command window and use dsregcmd.  Additional troubleshooting tips using this tool. https://learn.microsoft.com/en-us/azure/active-directory/devices/troubleshoot-device-dsregcmd

- If the password file or **Join-Domain-StudentVM.ps1** script has been removed from the student VM, you can reset the student VM or copy those files from the template VM.  If you also need to manually troubleshoot the script on the student VM, make sure you disable the scheduled startup task on the template VM (if applicable) before you reset the student VM; otherwise, the script will run automatically when you start the student VM.

- If you've inadvertently rename or domain join the template VM, to reset the template back to it's original state you must _manually_ revert the changes.  To manually revert a domain join, you should remove the VM from the domain by changing from a domain to a workgroup named "WORKGROUP".  Once this has been completed, rename the machine to "Lab00000".

# Increasing security
The instructions above use the VM's default local admin account.  If you want additional security, instead of using the default local admin account, you can add a secondary local adiministrator account (Security User) on the VM.  In this case, login to the template using the new Security User local account and run the **Set-DomainJoinValuesToSecretStore-TemplateVM.ps1**.  This will add an additional layer to help protect any secrets.  

Students should log into their lab VM using their domain account; students _shouldn't_ be given access to the local accounts that have administrator permission.

# Design Decisions
### - In the V1 domain join scripts the specific student was added to the vm. Why do I need to pass in the AAD group?
 - We wanted to remove the individual student vms communicating with Azure Lab Services to keep the scripts as self contained as possible.
 ### - Why do I need to add a lab "prefix"?
 - Since there isn't any direct connection between the lab information and the device data in AAD/Endpoint management, this prefix will allow queries in AAD/Endpoint to show which devices are in a specific lab.
 ### - Is the password file encrypted? Can anyone access it?
 - The Export-CliXml cmd creates an encrypted file on Windows that only the specific user that created the file can decrypt.
 

