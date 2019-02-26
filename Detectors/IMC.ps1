$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "IMC"
$cred = (Receive-Credential -SavedCredential "myIMCUser")
$imcserver = "myIMCHost.fqdn"
$uri = 'http://' + $imcserver + ':8080/imcrs/fault/alarm?start=0&size=1000&isAdmin=true'
$knownStatuses = @("Critical","Major","Minor","Info")
$ignore = @{
 "MyDevice1" = "NMS Performance Alarm";
 "MyDevice2" = "Another alarm type"
}

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
try {$alarms = Invoke-RestMethod -Uri $uri -method GET -Credential $cred -ContentType "application/xml" -EA stop -WA stop}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to $imcserver"
  $Disconnected = $True
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected)
{
  If (!$alarms.list.alarm)
  {
    $localEvent.descriptionDetails = "Unable to receive alarms from $imcserver"
    $localEvent.status = 'grey'
    $localEvent.eventShort = "Unable to receive alarms from $imcserver because the alarm array is empty"
  }
  else
  {
    $imcalarms = $alarms.list.alarm | where {($_.ackStatusDesc -match "Unacknowledged") -and ($_.alarmLevelDesc -notmatch "Info") -and ($_.alarmLevelDesc -notmatch "Info") -and ($_.recStatusDesc -notlike "Recovered")} | select `
    @{n="Device";e={$_.deviceName}},`
    @{n="Severity";e={$_.alarmLevelDesc}},`
    @{n="Alarm";e={$_.alarmCategoryDesc}},`
    @{n="Time";e={$_.faultTimeDesc}},`
    @{n="Status";e={"grey"}},`
    @{n="Ignore";e={$false}}
    If (!$imcalarms)
    {
      $localEvent.descriptionDetails = "No active alerts on $imcserver"
      $localEvent.status = 'green'
      $localEvent.eventShort = "No active alerts on $imcserver"  
    }
    else 
    {
      foreach ($i in $imcalarms)
      {
        if ($ignore.$($i.Device) -like $i.Alarm) {$i.Ignore = $true; $i.Status = "green"}
        elseif ($i.Severity -like "Critical") {$i.Status = "red"}
        elseif ($i.Severity -like "Major") {$i.Status = "yellow"}
        elseif ($i.Severity -like "Minor") {$i.Status = "green"}
        else {$i.Status = "grey"}
      }
      $noCritical = Get-ItemCount ($imcalarms | where {$_.Severity -like "Critical"})
      $noMajor = Get-ItemCount ($imcalarms | where {($_.Severity -like "Major")})
      $noMinor = Get-ItemCount ($imcalarms | where {($_.Severity -like "Minor")})
      $noUnknown = Get-ItemCount ($imcalarms | where {$_.Severity -notin $knownStatuses})
      if ($imcalarms.Status -match "red") 
      {
        $localEvent.status = "red"
      }
      elseif ($imcalarms.Status -match "yellow") 
      {
        $localEvent.status = "yellow"
      }
      elseif ($imcalarms.Status -match "grey") 
      {
        $localEvent.status = "grey"
      }
      Else {$localEvent.status = "green"}
      $localEvent.eventShort = "$noCritical Critical alarms, $noMajor Major alarms, $noMinor Minor alarms"
      if ($noUnknown -gt 0) {$localEvent.eventShort += ", $noUnknown alarms with unknown severity"}
      $localEvent.descriptionDetails = ($imcalarms | ConvertTo-Json)
      $localEvent.contentType = "json"
    }
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
