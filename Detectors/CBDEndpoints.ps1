$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "CBD Endpoints"
$CDBToken = Receive-Credential -SavedCredential MyCBDToken -Type ClearText
$connectorId = "MyCBDconnetorID"
$uri = "https://MyCBDHost.conferdeploy.net/integrationServices/v3/device?start=1&rows=5000"
$header = @{"X-Auth-Token" = "$CDBToken/$connectorId"}

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
try {$response = Invoke-RestMethod -Uri $uri -header $header -contenttype "application/json;charset=utf8" -method GET -ea Stop}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to CBD API"
  $Disconnected = $True
}
if (!$Disconnected) 
{
  if (!$response.success)
  {
    $localEvent.descriptionDetails = $response.message
    $localEvent.status = 'grey'
    $localEvent.eventShort = "Error when collecting from CBD API"
    $Uncollected = $true
  }
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected -and !$Uncollected)
{
  $report = $response.results | Select-Object @{n="User"; e={$_.email}}, @{n="Device"; e={$_.name}}, @{n="OS"; e={$_.osVersion}}, @{n="Policy"; e={$_.policyName}}, @{n="Sensor"; e={$_.sensorVersion}}, @{n="OutOfDate"; e={$_.SensorOutOfDate}}, @{n="State"; e={$_.status}}, @{n="Quarantined"; e={$_.quarantined}}, @{n="Status"; e={$_.color}}
  foreach ($device in $report)
  {
    if ($device.quarantined) {$device.status = "red"}
    elseif ($device.state -eq "BYPASS") {$device.status = "yellow"}
    else {$device.status = "green"}
  }
  $noRed = Get-ItemCount ($report | where {$_.status -like "red"})
  $noYellow = Get-ItemCount ($report | where {$_.status -like "yellow"})
  $noOutDated = Get-ItemCount ($report | where {$_.OutOfDate -like "True"})
  if ($noRed -gt 0) 
    {$localEvent.status = "red"}
  elseif ($noYellow -gt 0 -or $noOutDated -gt 0) 
    {$localEvent.status = "yellow"}
  else 
    {$localEvent.status = "green"}
  $localEvent.eventShort = "$noRed quarantined, $noYellow bypassed, $noOutDated outdated versions"
  $localEvent.descriptionDetails = ($report | sort status -Descending | where {$_.status -ne "green"} | ConvertTo-Json)
  $localEvent.contentType = "json"
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
