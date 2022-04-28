
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-LabsCsv {
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $CsvConfigFile
    )

    function Import-Schedules {
        param($schedules)

        $file = "./$schedules.csv"

        $scheds = Import-Csv $file
        $scheds | Foreach-Object {
            $_.WeekDays = ($_.WeekDays.Split(',')).Trim().Replace("; ", ";")
        }
        return $scheds
    }

    $labs = Import-Csv -Path $CsvConfigFile

    Write-Verbose ($labs | Format-Table | Out-String)

    # Validate that if a resource group\lab account appears more than once in the csv, that it also has the same SharedGalleryId and EnableSharedGalleryImages values.
    $lacs = $labs | Select-Object -Property ResourceGroupName, LabAccountName, SharedGalleryId, EnableSharedGalleryImages, Tags | Sort-Object -Property ResourceGroupName, LabAccountName
    $lacNames = $lacs | Select-Object -Property ResourceGroupName, LabAccountName, Tags -Unique
  
    foreach ($lacName in $lacNames){
        $matchLacs = $lacs | Where-Object {$_.ResourceGroupName -eq $lacName.ResourceGroupName -and $_.LabAccountName -eq $lacName.LabAccountName}
        $firstLac = $matchLacs[0]
  
        $mismatchSIGs = $matchLacs | Where-Object {$_.SharedGalleryId -ne $firstLac.SharedGalleryId -or $_.EnableSharedGalleryImages -ne $firstLac.EnableSharedGalleryImages}
        $mismatchSIGs | Foreach-Object {
            $msg1 = "SharedGalleryId - Expected: $($firstLac.SharedGalleryId) Actual: $($_.SharedGalleryId)"
            $msg2 = "EnabledSharedGalleryImages - Expected: $($firstLac.EnableSharedGalleryImages) Actual: $($_.EnableSharedGalleryImages)"
            Write-Error "Lab account $lacName SharedGalleryId and EnableSharedGalleryImages values are not consistent. $msg1. $msg2."
        }
    }

    $labs | ForEach-Object {

        # First thing, we need to save the original properties in case they're needed later (for export)
        Add-Member -InputObject $_ -MemberType NoteProperty -Name OriginalProperties -Value $_.PsObject.Copy()

        # Validate that the name is good, before we start creating labs
        if (-not ($_.LabName -match "^[a-zA-Z0-9_, '`"!|-]*$")) {
            Write-Error "Lab Name '$($_.LabName)' can't contain special characters..."
        }

        if ((Get-Member -InputObject $_ -Name 'AadGroupId') -and ($_.AadGroupId)) {
            # Validate that the aadGroupId (if it exists) isn't a null guid since that's not valid (it's in the default csv this way)
            if ($_.AadGroupId -ieq "00000000-0000-0000-0000-000000000000") {
                Write-Error "AadGroupId cannot be all 0's for Lab '$($_.LabName)', please enter a valid AadGroupId"
            }

            # We have to ensure 
            if ((Get-Member -InputObject $_ -Name 'MaxUsers') -and ($_.MaxUsers)) {
                Write-Warning "Max users and AadGroupId cannot be specified together, MaxUsers will be ignored for lab '$($_.LabName)'"
                $_.MaxUsers = ""
            }
        }

        # Checking to ensure the user has changed the example username/passwork in CSV files
        if ($_.UserName -and ($_.UserName -ieq "test0000")) {
            Write-Warning "Lab $($_.LabName) is using the default UserName from the example CSV, please update it for security reasons"
        }
        if ($_.Password -and ($_.Password -ieq "Test00000000")) {
            Write-Warning "Lab $($_.LabName) is using the default Password from the example CSV, please update it for security reasons"
        }

        if ((Get-Member -InputObject $_ -Name 'Emails') -and ($_.Emails)) {
            # This is to force a single email to an array
            $emailValues = @()
            $emailValues += ($_.Emails.Split(';')).Trim()
            $_.Emails = $emailValues
        }
        else {
            #Assign to empty array since New-AzLab expects this property to exist, but this property should be optional in the csv
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "Emails" -Value @() -Force
        }

        if ((Get-Member -InputObject $_ -Name 'LabOwnerEmails') -and ($_.LabOwnerEmails)) {
            $_.LabOwnerEmails = ($_.LabOwnerEmails.Split(';')).Trim()
        }
        else {
            #Assign to empty array since New-AzLab expects this property to exist, but this property should be optional in the csv
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "LabOwnerEmails" -Value @() -Force
        }

        # TODO: There are two odd things about this code:
        #   1.) The name of this property on the input object is "SharedPassword", but the the New-AzLab function expects the parameter name to be "SharedPasswordEnabled".
        #   2.) The Set-AzLab function expects this property to have Enabled\Disabled values, but New-AzLab expects true\false.
        # In the future, we need to resolve these inconsistencies. It works right now because:
        #   1.) New-AzLabsBulk calls New-AzLab to create a new lab.  When New-AzLab is called, it ignores this "SharedPassword" property value and defaults it to False because New-AzLab is expecting the property to be named "SharedPasswordEnabled".
        #   2.) New-AzLabsBulk then calls Set-AzLab.  When Set-AzLab is called, the value of this "SharedPassword" property is explicitly passed in as the "SharedPasswordEnabled" parameter.
        if (Get-Member -InputObject $_ -Name 'SharedPassword') {
            if (($_.SharedPassword -ne "Enabled") -or ($_.SharedPassword -ne "Disabled")) {
                if (($_.SharedPassword -eq "True") -or ($_.SharedPassword -eq "False")) {
                    if ([System.Convert]::ToBoolean($_.SharedPassword)) {
                        $_.SharedPassword = 'Enabled'
                    } else {
                        $_.SharedPassword = 'Disabled'
                    }
                } else {
                    $_.SharedPassword = 'Disabled'
                }
            }
        } else {
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "SharedPassword" -Value 'Disabled' -Force
        }

        if (Get-Member -InputObject $_ -Name 'GpuDriverEnabled') {
            if (($_.GpuDriverEnabled -eq "True") -or ($_.GpuDriverEnabled -eq "False")) {
                if ([System.Convert]::ToBoolean($_.GpuDriverEnabled)) {
                    $_.GpuDriverEnabled = $True
                } else {
                    $_.GpuDriverEnabled = $False
                }
            } else {
                $_.GpuDriverEnabled = $False
            }
        } else {
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "GpuDriverEnabled" -Value $false -Force
        }

        if (Get-Member -InputObject $_ -Name 'LinuxRdp') {
            if (($_.LinuxRdp -eq "True") -or ($_.GpuDriverEnabled -eq "False")) {
                if ([System.Convert]::ToBoolean($_.LinuxRdp)) {
                    $_.LinuxRdp = $true
                } else {
                    $_.LinuxRdp = $false
                }
            } else {
                $_.LinuxRdp = $false
            }
        }
        else {
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "LinuxRdp" -Value $false -Force
        }

        if ((Get-Member -InputObject $_ -Name 'Schedules') -and ($_.Schedules)) {
            Write-Verbose "Setting schedules for $($_.LabName)"
            $_.Schedules = Import-Schedules -schedules $_.Schedules
        }
        else {
            #Assign to empty array since New-AzLab expects this property to exist, but this property should be optional in the csv
            Add-Member -InputObject $_ -MemberType NoteProperty -Name "Schedules" -Value @() -Force
        }

    }

    Write-Verbose ($labs | ConvertTo-Json -Depth 10 | Out-String)

    return ,$labs # PS1 Magick here, the comma is actually needed. Don't ask why.
    # Ok, here is why, PS1 puts each object in the collection on the pipeline one by one
    # unless you say explicitely that you want to pass it as a single object
}

function Export-LabsCsv {
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]
        $labs,

        [parameter(Mandatory = $true)]
        [string]
        $CsvConfigFile,

        [parameter(Mandatory = $false)]
        [switch] $Force
    )

    begin
    {
        $outArray = @()
    }

    process
    {
        # Iterate over the labs and pull out the inner properties (orig object) and add in result fields
        $labs | ForEach-Object {
            $obj = $_

            # If we don't have the underlying properties, need to bail out
            if (-not (Get-Member -InputObject $_ -Name OriginalProperties)) {
                Write-Error "Cannot write out labs CSV, input labs object doesn't contain original properties"
            }

            $outObj = $_.OriginalProperties

            # We need to copy any 'result' fields over to the original object we're writing out
            Get-Member -InputObject $obj -Name "*Result" | ForEach-Object {
                if (Get-Member -InputObject $outObj -Name $_.Name) {
                    $outObj.$($_.Name) = $obj.$($_.Name)
                }
                else {
                    Add-Member -InputObject $outObj -MemberType NoteProperty -Name $_.Name $obj.$($_.Name)
                }
            }

            # Add the object to the cumulative array
            $outArray += $outObj
        }
    }

    end
    {
        if ($Force.IsPresent) {
            $outArray | Export-Csv -Path $CsvConfigFile -NoTypeInformation -Force
        }
        else {
            $outArray | Export-Csv -Path $CsvConfigFile -NoTypeInformation -NoClobber
        }
    }
}

function Watch-Jobs {
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]
        $labs,

        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]
        $jobs,

        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $resultColumnName

    )

    Write-Host "Waiting for jobs to complete."
    $jobs.Values | Wait-Job

    foreach ($currentJob in $jobs.GetEnumerator()) {

        $labForJob = $labs | Where-Object {($_.ResourceGroupName -eq $($currentJob.Key.Split(":")[0])) -and ($_.LabName -eq $($currentJob.Key.Split(":")[1]))}
        if ($labForJob) {
            
            if ([string]::IsNullOrEmpty($currentJob.Value.Error) -and [string]::IsNullOrEmpty($currentJob.Value.Warning)) {
                Add-Member -InputObject $labForJob -MemberType NoteProperty -Name $resultColumnName -Value "Success" -Force
            } else {
                Add-Member -InputObject $labForJob -MemberType NoteProperty -Name $resultColumnName -Value "Failed: $($currentJob.Value.Warning + ":" + $currentJob.Value.Error)" -Force
            }
            #Remove-Job -Job $currentJob.Value | Out-Null
        } else {
            Write-Host "Unable to match job with lab: $($currentJob.Key)"
        }
    }
    return $labs
}

Export-ModuleMember -Function   Import-LabsCsv,
                                Export-LabsCsv,
                                Watch-Jobs