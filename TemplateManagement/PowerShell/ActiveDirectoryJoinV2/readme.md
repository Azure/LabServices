# Domain Joining student VMs

## How to setup the template VM
### Information you'll need
- User name and password that allows the vm to join the domain.
- Domain name to join
- Lab name prefix, the vms will need unique names and this will help identify the lab the vms are in.
- A secret store password.  This will need to be different than the user password or the domain user password.
- Azure Active Directory group name for the lab.
### How to setup the lab template.
- Start template VM and connect using the administor.
- Before setting up the Domain joining scripts make sure that the template vm is ready.  Add or configure any software before doing this.
- Copy down the SetupTemplateToDomainJoin.ps1
- Run the SetupTemplateToDomainJoin.ps1 as administrator.
- Fill in the requested information.
    - SecureStore password
    - Domain join user name
    - Domain join user password
    - AAD group name
    - Lab prefix
    - Current user password
### What is the SetupTemplateToDomainJoin script doing?
The script is doing several actions
- Create a securestore with and encrypted password file.
- Add secrets to the securestore.
- Copy down the DomainJoin.ps1 script that will be run on the student vm.
- Create task that is scheduled to run on startup using the administrator credentials. See increase security for variations.

On the template vm the script will create a secretstore that is specific to the current logged in user with the password entered.  The password is stored in an encrypted file specific to the user.  Additional secrets are added to the securestore to be accessed by the domain join script.  The Domainjoin script is downloaded from the repository and stored in the public documents folder.

## What is the DomainJoin script do.
The script does several actions:
- Rename the student vm using the lab prefix and a random number.  Unique vm names are required to domain join.
- Add the computer to the domain.
- Add the AAD group to the remote desktop users group.
- Remove the encrypted password file.
- Remove the DomainJoin-StudentVM script
- Restart the vm.

### Increase security
The instructions above use the labs default administrator.  If you want to have additional security, instead of using the lab administrator you can add another user (Security User) and add that user as an administrator.  Login to the template using the new security user and run the SetupTemplateToDomainJoin.ps1.  This will add an additional layer to help protect any secrets.

# Rename student VMs to unique names
## How to setup the template VM
### Information you'll need
- Lab name prefix, the vms will need unique names and this will help identify the lab the vms are in.
- A secret store password.  This will need to be different than the user password or the domain user password.

### How to setup the lab template.
- Start template VM and connect using the administor.
- Copy down the SetupTemplateToRenameVM.ps1
- Run the SetupTemplateToRenameVM.ps1 as administrator.
- Fill in the requested information.
    - SecureStore password
    - Lab prefix
    - Current user password
### What is the SetupTemplateToRenameVM script doing?
The script is doing several actions
- Create a securestore with and encrypted password file.
- Add secrets to the securestore.
- Copy down the RenameVM.ps1 script that will be run on the student vm.
- Create task that is scheduled to run on startup using the administrator credentials.

On the template vm the script will create a secretstore that is specific to the current logged in user with the password entered.  The password is stored in an encrypted file specific to the user.  Additional secrets are added to the securestore to be accessed by the RenameVM script.  The RenameVM script is downloaded from the repository and stored in the public documents folder.  The last step is to create a scheduled task that runs the RenameVM.ps1 under the administrator credentials at startup.

## What is the RenameVM script do.
The script does several actions:
- Rename the student vm using the lab prefix and a random number.  Unique vm names are required to domain join.
- Remove the encrypted password file.
- Restart the vm.


# Design Decisions
### - Why use the template IP?  Can I use this technique to determine the template?
 - We wanted to keep the scripts small and quick, so we used the template IP versus getting the Lab VM details.  There is a chance that the template IP could change.  For other uses it is recommended to use the Lab VM properties to determine the template vm.
### - In the V1 domain join scripts the specific student was added to the vm. Why do I need to pass in the AAD group?
 - We wanted to remove the individual student vms communicating with Azure Lab Services to keep the scripts as self contained as possible.
 ### - Why isn't the task automatically created?  The code is commented out.
 - As this is sample code, it should be an explicit action to create the task either manually or by removing the comments from that section of the code.
 ### - Why do I need to add a lab "prefix"?
 - Since there isn't any direct connection between the lab information and the device data in AAD/Endpoint management, this prefix will allow queries in AAD/Endpoint to show which devices are in a specific lab.
 ### - Is the password file encrypted? Can anyone access it?
 - The Export-CliXml cmd creates an encrypted file on Windows that only the specific user that created the file can decrypt.
 

