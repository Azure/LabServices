[CmdletBinding()]
param(
    [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CsvConfigFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Make sure the input file does exist
if (-not (Test-Path -Path $CsvConfigFile)) {
    Write-Error "Input CSV File must exist, please choose a valid file location..."
}

Import-Module ".\Utilities.psm1"

$scriptstartTime = Get-Date
Write-Host "Executing Bulk Add Schedules Script, starting at $scriptstartTime" -ForegroundColor Green

$labs = Import-LabsCsv $CsvConfigFile

ForEach ($lab in $labs) {
    try {
        $currentLab = Get-AzLabServicesLab -Name $lab.LabName -ResourceGroupName $lab.ResourceGroupName
        if ($lab.Schedules) {
            Write-Host "Adding Schedules for $($lab.LabName)."

            foreach($schedule in $lab.Schedules) {
                $sdate = [datetime]::Parse($schedule.FromDate)
                $stime = [datetime]::Parse($schedule.StartTime.Replace('"',''))
                $startd = [datetime]::New($sdate.Year, $sdate.Month, $sdate.Day, $stime.Hour, $stime.Minute, 0)
                $fullStart = $startd.ToString('u')

                $etime = [datetime]::Parse($schedule.EndTime.Replace('"',''))
                $endd = [datetime]::New($sdate.Year, $sdate.Month, $sdate.Day, $etime.Hour, $etime.Minute, 0)
                $fullEnd = $endd.ToString('u')

                $edate = [datetime]::Parse($schedule.ToDate.Replace('"',''))
                $duntil = [datetime]::New($edate.Year, $edate.Month, $edate.Day, 23, 59, 59)
                $fullUntil = $duntil.ToString('u')

                [Microsoft.Azure.PowerShell.Cmdlets.LabServices.Support.WeekDay[]]$weekdays = $null
                foreach ($day in ($schedule.WeekDays -Split ";")) {
                    $weekdays += [Microsoft.Azure.PowerShell.Cmdlets.LabServices.Support.WeekDay]$day.Trim("""").ToString()
                }
                # Check if schedules exist.
                $zschedules = $currentLab | Get-AzLabServicesSchedule
                if (!($zschedules | Where-Object {(($startd -ge $_.StartAt) -and ($startd -le $_.StopAt)) -or (($endd -ge $_.StartAt) -and ($endd -le $_.StopAt))})) {
                #if (!($currentLab | Get-AzLabServicesSchedule)) {
                    if ($schedule.Frequency -eq "Once") {
                        New-AzLabServicesSchedule -Lab $currentLab -Name $('Default_' + (Get-Random -Minimum 10000 -Maximum 99999)) -Note $($schedule.Notes) `
                            -StartAt $fullStart `
                            -StopAt $fullEnd `
                            -TimeZoneId $($schedule.TimeZoneId) | Out-Null
                    } else {
                        New-AzLabServicesSchedule -Lab $currentLab -Name $('Default_' + (Get-Random -Minimum 10000 -Maximum 99999)) -Note $($schedule.Notes) `
                            -RecurrencePatternExpirationDate $fullUntil `
                            -RecurrencePatternFrequency $($schedule.Frequency) `
                            -RecurrencePatternInterval 1 `
                            -RecurrencePatternWeekDay $weekdays `
                            -StartAt $fullStart `
                            -StopAt $fullEnd `
                            -TimeZoneId $($schedule.TimeZoneId) | Out-Null
                    }
                } else {
                    Write-Host "Duplicate schedules not added on lab $($currentLab.Name)"
                }
            }

            Write-Host "Added all schedules."
        }
    } catch {        
        Write-Host "Unable to add schedules to Lab: $($lab.LabName) in $($lab.ResourceGroupName): Error message: $_"
    }
}

Write-Host "Completed running Bulk Add Schedules script, total duration $([math]::Round(((Get-Date) - $scriptstartTime).TotalMinutes, 1)) minutes" -ForegroundColor Green