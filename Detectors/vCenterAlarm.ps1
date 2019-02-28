$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "vCenter Alarm"
$myServer = "MyvCenterServer.fqdn"
$knownStatuses = @("red","yellow","green")
Import-Module -Name VMware.VimAutomation.Core

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
  Write-Warning "$detectorName is not activated. Run 'Set-Detector -name $detectorName -isActive $true' to activate the Detector"
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
try {$session = Connect-VIServer -Server $myServer -EA stop -WA silentlycontinue}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to $myServer"
  $Disconnected = $True
}
If (!$Disconnected)
{
  try {$rootFolder = Get-Folder "Datacenters" -EA stop -WA stop}
  catch {
    $localEvent.descriptionDetails = $_
    $localEvent.status = 'grey'
    $localEvent.eventShort = "Unable to collect data from $myServer"
    $Uncollected = $True
  }
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected -and !$Uncollected)
{
  $report = @()
  foreach ($ta in $rootFolder.ExtensionData.TriggeredAlarmState)
  {
    $alarm = "" | Select-Object Entity, EntityType, Reported, Status, Time, Acknowledged, AcknowledgedByUser, AcknowledgedTime
    $alarm.Reported = (Get-View -Server $visrvr $ta.Alarm).Info.Name
    $alarm.Entity = (Get-View -Server $vcsrvr $ta.Entity).Name
    $alarm.EntityType = (Get-View -Server $visrvr $ta.Entity).GetType().Name
    $alarm.Status = $ta.OverallStatus
    $alarm.Time = $ta.Time
    $alarm.Acknowledged = $ta.Acknowledged
    $alarm.AcknowledgedByUser = $ta.AcknowledgedByUser
    $alarm.AcknowledgedTime = $ta.AcknowledgedTime
    $report += $alarm
  }
  if (!$report)
  {
    $localEvent.descriptionDetails = "No active alarms on $myServer"
    $localEvent.status = 'green'
    $localEvent.eventShort = "No active alarms"
  }
  else 
  {
    $noRed = Get-ItemCount ($report | where {($_.Status -like "red") -and (!$_.Acknowledged)})
    $noYellow = Get-ItemCount ($report | where {($_.Status -like "yellow") -and (!$_.Acknowledged)})
    $noGreen = Get-ItemCount ($report | where {($_.Status -like "green")})
    $noUnknown = Get-ItemCount ($report | where {$_.Status -notin $knownStatuses})
    $noAck = Get-ItemCount ($report | where {$_.Acknowledged})
    $localEvent.eventShort = "$noRed Red alarms, $noYellow Yellow alarms"
    if ($noRed -gt 0) {$localEvent.status = "red"}
    elseif ($noYellow -gt 0) {$localEvent.status = "yellow"}
    elseif ($noUnknown -gt 0) 
    {
      $localEvent.status = "grey"
      $localEvent.eventShort += ", $noUnknown Unknown alarms"
    }
    else
    {
      $localEvent.status = "green"
      $localEvent.eventShort = "$noAck Acknowledged alarms"
    }
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
Disconnect-VIServer -Server $myServer -Confirm:$false
