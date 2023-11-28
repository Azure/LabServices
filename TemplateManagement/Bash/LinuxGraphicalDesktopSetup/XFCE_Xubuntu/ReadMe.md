# Introduction

These scripts install XFCE/X2Go and xUbuntu/X2Go graphical desktop environments on Ubuntu.

> [!NOTE]
> The Ubuntu 16.04, 18.04 and 21.04 LTS images are *no* longer available in the Azure marketplace as a free image provided by Canonical.  Azure Labs only supports using free marketplace images. The instructions/scripts included for Ubuntu 16.04/18.04/21.04 LTS are only applicable to custom lab images that were previously [saved to a Compute Gallery](https://learn.microsoft.com/azure/lab-services/approaches-for-custom-image-creation#save-a-custom-image-from-a-lab-template-virtual-machine), or to custom images that are imported from a [physical lab environment](https://learn.microsoft.com/azure/lab-services/approaches-for-custom-image-creation#bring-a-custom-image-from-a-vhd-in-your-physical-lab-environment).  Otherwise, we recommend using Ubuntu 20.04 or 22.04 LTS which are available as free marketplace images.

## Ubuntu

These scripts have been tested with:

    - Ubuntu 16.04/18.04/20.04/21.04/22.04 LTS

## Configuring X2Go

[X2Go](https://wiki.x2go.org/doku.php/doc:newtox2go) is a Remote Desktop solution, which sometimes is referred to as Remote Control. This is not to be confused with Microsoft Remote Desktop Connection that uses RDP - this is a competing Remote Desktop solution and protocol.

Using X2Go requires two steps: _(Students only need to do step #2 below to connect to their assigned VM)_

1. [Install the X2Go server](#install-x2go-server) on the lab's template VM using one of the scripts below.
2. [Install the X2Go client and create a session](#install-x2go-client-and-create-a-session) to connect to your lab (remote) VM.

### Install X2Go Server

The lab (remote) VM runs X2Go server. Graphical sessions are started on this remote VM and the server transfers the windows/desktops graphics to the client.

The scripts below automatically install the X2Go server and the Linux desktop environment.  To install using these scripts, SSH into the template VM and paste in one of the following scripts depending on which desktop environment you prefer:

#### Install XFCE4 Desktop and X2Go Server

```bash
sudo sh -c "$(curl -fsSL https://raw.githubusercontent.com/Azure/LabServices/main/TemplateManagement/Bash/LinuxGraphicalDesktopSetup/XFCE_Xubuntu/Ubuntu/x2go-xfce4.sh)"
```

#### Install Xubuntu Desktop & X2Go Server

```bash
sudo sh -c "$(curl -fsSL https://raw.githubusercontent.com/Azure/LabServices/main/TemplateManagement/Bash/LinuxGraphicalDesktopSetup/XFCE_Xubuntu/Ubuntu/x2go-xubuntu.sh)"
```
### Install X2Go Client and Create a Session

Once you have the X2Go\Xrdp server installed on your template VM (using the scripts above), you'll use the X2Go\RDP client to remotely connect to the VM. The X2Go\RDP Client is the application that allows you to connect to a remote server and display a graphical desktop on your local machine.

Read the following article:

- [Connect to student VM using X2Go](https://docs.microsoft.com/azure/lab-services/how-to-use-remote-desktop-linux-student#connect-to-the-student-vm-using-x2go)

After running the script, you may also want to disable compositing in xUbuntu desktop to optimize performance over a remote desktop connection.  For example, use the below script to disable compositing.  This script requires an active X11 display session, so you will need to run the script via a terminal within your xUbuntu graphical desktop environment by connecting to the VM using X2Go:

```bash
xfconf-query -c xfwm4 -p /general/use_compositing -s false
```

Once you've disabled compositing and restarted the VM, you should notice a significant performance improvement when using a remote desktop connection.