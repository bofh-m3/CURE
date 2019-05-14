$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "Slack Health"
$okStatus = @("ok","resolved")

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
try {$status = Invoke-RestMethod -Method Get -Uri "https://status.slack.com/api/current" -EA stop -WA silentlycontinue}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to Slack Status Current API"
  $Disconnected = $True
}

If (!$Disconnected)
{
  if ($status.status -notin $okStatus)
  {
    try {$history = Invoke-RestMethod -Method Get -Uri "https://status.slack.com/api/history" -EA stop -WA silentlycontinue}
    catch {
      $localEvent.descriptionDetails = $_
      $localEvent.status = 'grey'
      $localEvent.eventShort = "Unable to connect to Slack Status History API"
      $Uncollected = $True
    }
  }
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected -and !$Uncollected)
{
  if ($status.status -notin $okStatus)
  {
    $report = $history | where {$_.status -notlike "resolved"} | select id,`
     @{n="created";e={([datetime]$_.date_created).ToString()}},`
     @{n="updated";e={([datetime]$_.date_updated).ToString()}},`
     @{n="title";e={$_.title}},`
     @{n="type";e={$_.type}},`
     @{n="state";e={$_.status}},`
     @{n="services";e={$_.services -join ','}},`
     @{n="latest_details";e={$_.notes[0].body}},`
     @{n="status";e={$null}}

    $report.latest_details = $report.latest_details -replace "'"
    $report.title = $report.title -replace "'"

    foreach ($i in $report)
    {
      if ($i.type -like "outage") {$i.status = "red"}
      else {$i.status = "yellow"}
    }

    $localEvent.descriptionDetails = ($report | ConvertTo-Json)
    if ($status.type -like "outage") {$localEvent.status = 'red'}
    else {$localEvent.status = 'yellow'}
    $localEvent.eventShort = "$($status.title), $(([datetime]$status.date_updated).ToString())" -replace "'"
    $localEvent.contentType = "json"
  }
  else
  {
    $localEvent.descriptionDetails = ($status | ConvertTo-Json)
    $localEvent.status = 'green'
    $localEvent.contentType = "json"
    $localEvent.eventShort = "$($status.status), $(([datetime]$status.date_updated).ToString())"
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
<# this is custom #>
