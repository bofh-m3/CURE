$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
asnp VeeamPSSnapIn
$detectorName = "Veeam Backup"
$veeamsrv = "MyVeeamServer.fqdn"
$HoursSinceJobLastRunYellow = 50
$HoursSinceJobLastRunRed = 80
$knownStatuses = @("Success","Failed","Warning")
$warningExceptions = @{
  "MyVM1" = "Changed block tracking cannot be enabled: one or more snapshots present*";
  "MyVM2" = "Unable to truncate Microsoft SQL Server transaction logs*";
  "MyVM3" = "Another warning to surpress*"
}
$JobNameFilter = "BACKUP*"

############### GET DETECTOR SETTINGS AND VALIDATE CONNECTIVITY ####################
Try {$settings = Get-DetectorSettings $detectorName -EA stop}
Catch {Write-Log -scriptName $detectorName -errorMessage $_ -exit}
If (!($settings)) 
{
  Write-Log -scriptName $detectorName -errorMessage "$detectorName is not configured in database" -exit
}

####################### TEST IF SNOOZED OR NOT ACTIVE ##############################
If ($settings.isactive -ne 1) 
{
  Write-Warning "$detectorName is not activated. Run 'Set-Detector -name '$detectorName' -isActive $true' to activate the Detector"
  Sleep -s 10
  Exit
}
If (Test-IfSnoozed $settings.detectorid)
{
  Write-Host "$detectorName is snoozed"
  Sleep -s 10
  Exit
}

######################### CREATE DEFAULT LOCAL EVENT ###############################
$localEvent = Get-DefaultLocalEvent -DetectorName $detectorName -DetectorId $settings.detectorid

############################## CONNECT AND COLLECT #################################
<# this is custom #>
try {Connect-VBRServer -Server $veeamsrv -EA stop -WA silentlycontinue}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to $veeamsrv"
  $Disconnected = $True
}
If (!$Disconnected)
{
  try {$veeamjobs = Get-VBRJob -EA stop -WA silentlycontinue | where {($_.name -like $JobNameFilter) -and ($_.IsScheduleEnabled)}}
  catch {
    $localEvent.descriptionDetails = $_
    $localEvent.status = 'grey'
    $localEvent.eventShort = "Unable to collect jobs from $veeamsrv"
    $Uncollected = $True
  }
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected -and !$Uncollected)
{
  If (!$veeamjobs)
  {
    $localEvent.descriptionDetails = "There are no enabled jobs on $veeamsrv"
    $localEvent.status = 'grey'
    $localEvent.eventShort = "There are no enabled jobs on $veeamsrv"
  }
  else
  {
    $report = @()
    $failedjobs = $veeamjobs | where {([math]::Round(((get-date) - $_.Info.ScheduleOptions.LatestRunLocal).totalhours) -gt $HoursSinceJobLastRunYellow) -or ($_.Info.LatestStatus -notlike "Success")}
    if ($failedjobs)
    {
      foreach ($j in $failedjobs)
      {
        $Result = Get-VBRBackupSession | Where {$_.jobId -eq $j.Id.Guid} | Sort EndTimeUTC -Descending | Select -First 1
        $FailedVms=$Result.GetTaskSessions() | where {$_.status -notlike "success"}
        if (!$FailedVms)
        {
          $session=Get-VBRSession -Job $j -Last
          $message = ($session.Log | where {$_.Status -notlike "Succeeded"} | select -expand title) -join ''
          $report += "" | select @{n="JobName";e={$j.name}},@{n="VMName";e={$null}},@{n="State";e={$null}},@{n="Reason";e={$message}},@{n="HoursSinceLastRun";e={[math]::Round(((get-date) - $j.Info.ScheduleOptions.LatestRunLocal).totalhours)}},@{n="Status";e={$null}},@{n="Ignore";e={$false}}
        }
        else
        {
          $report += $FailedVms | select JobName,@{n="VMName";e={$_.Name}},@{n="State";e={$_.Status}},@{n="Reason";e={$_.info.Reason}},@{n="HoursSinceLastRun";e={[math]::Round(((get-date) - $j.Info.ScheduleOptions.LatestRunLocal).totalhours)}},@{n="Status";e={$null}},@{n="Ignore";e={$false}}
        }
      }
      foreach ($r in $report)
      {
        if (!$r.State)
        {
          if ($r.HoursSinceLastRun -gt $HoursSinceJobLastRunRed) {$r.State = "Failed"; $r.Reason = "Job not run in more than $HoursSinceJobLastRunRed hours"}
          elseif ($r.HoursSinceLastRun -gt $HoursSinceJobLastRunYellow) {$r.State = "Warning"; $r.Reason = "Job not run in more than $HoursSinceJobLastRunYellow hours"}
          else {$r.State = "Unknown"; $r.Reason = "Unable to get reason"}
        }
        if (!$r.VMName) {$r.VMName = "-"}
        if ($r.State -like "Failed") {$r.Status = "red"}
        elseif (($r.State -like "Warning") -and ($r.Reason -like $warningExceptions.$($r.VMName))) {$r.Status = "green"; $r.Ignore = $true}
        elseif ($r.State -like "Warning") {$r.Status = "yellow"}
        else {$r.Status = "grey"}
      }
    }
    else
    {
      $report = $veeamjobs | select @{n="JobName";e={$_.name}},@{n="VMName";e={"-"}},@{n="State";e={$_.Info.LatestStatus.ToString()}},@{n="Reason";e={$null}},@{n="HoursSinceLastRun";e={[math]::Round(((get-date) - $_.Info.ScheduleOptions.LatestRunLocal).totalhours)}},@{n="Status";e={"green"}},@{n="Ignore";e={$false}}
    }
    $noRed = (Get-ItemCount ($report | where {$_.Status -like "red"}))
    $noYellow = (Get-ItemCount ($report | where {$_.Status -like "yellow"}))
    $noGrey = (Get-ItemCount ($report | where {$_.Status -like "grey"}))
    $noEnabledJobs = (Get-ItemCount $veeamjobs)
    if ($noRed -ge 1) {$localEvent.status = "red"}
    elseif ($noYellow -ge 1) {$localEvent.status = "yellow"}
    elseif ($noGrey -ge 1) {$localEvent.status = "grey"}
    else {$localEvent.status = "green"}
    $localEvent.eventShort = "$noRed Red alerts, $noYellow Yellow alerts, $noGrey Grey alerts, $noEnabledJobs Enabled jobs"
    $localEvent.descriptionDetails = ($report | ConvertTo-Json)
    $localEvent.contentType = "json"
  }
}

################# COMPARE WITH LAST EVENT AND WRITE NEW EVENT ######################
If (Test-IfNewEvent $LocalEvent)
{
  Write-Event $LocalEvent
}

############################## WRITE HEARTBEAT #####################################
Write-HeartBeat $settings.detectorid

################################### CLEANUP ########################################
Disconnect-VBRServer
