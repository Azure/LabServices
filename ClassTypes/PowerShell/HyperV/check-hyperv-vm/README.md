# Check my Hyper-V VMs

[Test-HypervVmConfig](./Test-HypervVmConfig.ps1) will verify you setup follows best practices for nested virtualization.  

For all local users:

- Verify user can use Hyper-V.

For each Hyper-V client VM:

- Verify the Hyper-V VM is **not** in a saved state.  
- Verify the AutomaticStopAction is set to Stop.
- Check the number of vCPUs.
- Verify adequate memory assigned.
- Verify variable memory enabled.
- Verify disks are VHDX.

For the host VM:

- Verify DHCP role is not installed.
- Verify sufficient free space on OS disk.

## Usage

In an Adminstrator PowerShell window, run:

```powershell
./Test-HypervVmConfig.ps1
```

In some cases, the suggested defaults may not apply to your Hyper-V VM.  To override the defaults for a VM, provide a config file.  Schema for config file is available at [vm-config-schema.json](vm-config-schema.json).

For example:

```powershell
./Test-HypervVmConfig.ps1 -$ConfigFilePath ./ethical-hacking-vm-config.json.
```
