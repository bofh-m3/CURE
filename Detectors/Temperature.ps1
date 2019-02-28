$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "Temperature"
$thermo = "My-HWg-STE.fqdn"
$lowyellow = 18
$lowred = 16
$highyellow = 28
$highred = 30
$historyevents = 100

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
try {$fetch = Invoke-RestMethod -Method Get -Uri "http://$thermo/index_m.asp" -EA stop -WA silentlycontinue}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to $thermo"
  $Disconnected = $True
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected)
{
  $report = Get-ODBCData -query "SELECT datetime,status,eventshort FROM $eventTable WHERE detectorId = $($localevent.detectorID) ORDER BY eventId DESC LIMIT $historyevents"
  $report | Add-Member -MemberType NoteProperty -Name "reading" -Value $null
  foreach ($i in $report)
  {
    if ($i.eventshort -like "Current temperature is *") {$i.reading = $i.eventshort -replace 'Current temperature is '}
  }
  $temp = ($fetch -split '<td  id=alse215><div class="value" id="s215">' | select -Index 1) -split '&nb' | select -Index 0
  $localEvent.descriptionDetails = ($report | select reading,@{n="date";e={$_.datetime.ToString()}},status,eventshort) | ConvertTo-Json
  $localEvent.contentType = "json"
  $localEvent.eventShort = "Current temperature is $temp"
  if (($temp -lt $lowred) -or ($temp -gt $highred)) {$localEvent.status = 'red'}
  elseif (($temp -lt $lowyellow) -or ($temp -gt $highyellow)) {$localEvent.status = 'yellow'}
  elseif (($temp -ge $lowyellow) -and ($temp -le $highyellow)) {$localEvent.status = 'green'}
  else {$localEvent.status = 'grey'}
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
