$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "Netskope"
$knownLocations = @("Location1","Location2")
$knownIPs = @("xxx.xxx.xxx.xxx","yyy.yyy.yyy.yyy")
$key = Receive-Credential -SavedCredential MyAPIKey -Type ClearText
$baseUrl = "https://MyTennant.goskope.com/api/v1/alerts?token=" + $key + "&timeperiod=2592000&acked=false"
$queries = @{
 DLP = "&type=DLP&query=dlp_rule_severity in ['Critical','High','Medium']"
 Anomaly = "&type=anomaly&query=risk_level eq 'high'"
 'Compromised Credential' = "&query=alert_type eq 'Compromised Credential'"
 Malware = "&query=alert_type eq 'Malware'"
 Watchlist = "&query=alert_type eq 'watchlist'"
 'Security Assessment' = "&query=alert_type eq 'Security Assessment'"
 Remediation = "&query=alert_type eq 'Remediation'"
 Quarantine = "&query=alert_type eq 'quarantine'"
 Policy = "&query=alert_type eq 'policy'"
 Malsite = "&query=alert_type eq 'malsite'"
 'Legal Hold' = "&query=alert_type eq 'Legal Hold'"
}
Function Convert-FromUnixDate ($UnixDate) {
   [timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds($UnixDate))
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls

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
$collect = @()
foreach ($key in $queries.keys)
{
  $url = $baseUrl + $queries.$key
  try {$fetch = Invoke-RestMethod $url -EA stop}
  catch {
    $localEvent.descriptionDetails = $_
    $localEvent.status = 'grey'
    $localEvent.eventShort = "Unable to get Netskope data"
    $Disconnected = $True
    Continue
  }
  $collect += "" | select `
   @{n="Name";e={$key}},`
   @{n="state";e={$fetch.status}},`
   @{n="status";e={$null}},`
   @{n="msg";e={$fetch.msg + '-' + $($fetch.errors -join ', ') + '-' + $fetch.errorCode}},`
   @{n="data";e={$fetch.data}}
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected)
{
  $alerts = @()
  foreach ($i in $collect)
  {
    if (!$i.data)
    {
      if ($i.state -notlike "success")
      {
        $alerts += "" | select `
         @{n="alert_type";e={$i.Name}},`
         @{n="dlp_incident_id";e={$null}},`
         @{n="alert_name";e={"CURE"}},`
         @{n="app";e={"CURE"}},`
         @{n="object";e={$i.state + '-' + $i.msg}},`
         @{n="user";e={$null}},`
         @{n="exposure";e={$null}},`
         @{n="dlp_rule_severity";e={$null}},`
         @{n="risk_level";e={$null}},`
         @{n="breach_score";e={$null}},`
         @{n="timestamp";e={$null}},`
         @{n="alerts";e={$null}},`
         @{n="status";e={"grey"}}
      }
    }
    else
    {
      foreach ($alert in $i.data)
      {
        if ($alert.object)
        {
          $objArr = $alert.object -split '/'
          if ($objArr.count -gt 1) {$object = '~' + $objArr[-1]}
          else {$object = $alert.object}
        }
        else {$object = $alert.user}
        if ($alert.dlp_rule_severity -like "critical") {$status = "red"}
        elseif (($alert.exposure -in @("public","external")) -and ($alert.dlp_rule_severity -like "High")) {$status = "red"}
        elseif ($alert.dlp_rule_severity -like "High") {$status = "yellow"}
        elseif (($alert.exposure -in @("public","external")) -and ($alert.dlp_rule_severity -like "Medium")) {$status = "yellow"}
        elseif ($alert.dlp_rule_severity -like "Medium") {Continue}
        elseif (($alert.alert_type -like "anomaly") -and ($alert.event_type -like "risky_country") -and ($alert.src_location -like $knownLocations) -and ($alert.userip -in $knownIPs)) {Continue}
        else {$status = "yellow"}
        $alerts += $alert | select alert_type,dlp_incident_id,alert_name,app,@{n="object";e={$object}},user,exposure,dlp_rule_severity,risk_level,breach_score,@{n="timestamp";e={(Convert-FromUnixDate $alert.timestamp).ToString()}},@{n="status";e={$status}}
      }
    }
  }
  $report = @()
  foreach ($t in ($alerts.alert_type | select -Unique))
  {
    $ctype = $alerts | where {$_.alert_type -eq $t}
    foreach ($o in ($ctype.object | select -unique))
    {
      $cobj = $ctype | where {$_.object -eq $o}
      if ($cobj.status -match "red") {$cstatus = "red"}
      elseif ($cobj.status -match "yellow") {$cstatus = "yellow"}
      else {$cstatus = "grey"}
      $report += "" | select `
       @{n="alert_type";e={$t}},`
       @{n="dlp_incident_id";e={($cobj.dlp_incident_id | select -unique) -join ', '}},`
       @{n="alert_name";e={($cobj.alert_name | select -unique) -join ', '}},`
       @{n="app";e={($cobj.app | select -unique) -join ', '}},`
       @{n="object";e={$o}},`
       @{n="user";e={($cobj.user | select -unique) -join ', '}},`
       @{n="exposure";e={($cobj.exposure | select -unique) -join ', '}},`
       @{n="dlp_rule_severity";e={($cobj.dlp_rule_severity | select -unique) -join ', '}},`
       @{n="risk_level";e={($cobj.risk_level | select -unique) -join ', '}},`
       @{n="breach_score";e={($cobj.breach_score | select -unique) -join ', '}},`
       @{n="timestamp";e={($cobj.timestamp | sort)[0]}},`
       @{n="alerts";e={(Get-ItemCount $cobj)}},`
       @{n="status";e={$cstatus}}
    }
  }
  $noDLP = Get-ItemCount ($report | where {$_.alert_type-like "DLP"})
  $noAnomaly = Get-ItemCount ($report | where {$_.alert_type-like "anomaly"})
  $noCredential = Get-ItemCount ($report | where {$_.alert_type-like "Compromised Credential"})
  $noOther = Get-ItemCount ($report | where {$_.alert_type -notin @("Compromised Credential","DLP","anomaly")})
  $localEvent.eventShort = "$noDLP DLP incidents, $noAnomaly Anomalies, $noCredential Compromised, $noOther Other event types"
  if ($report.Status -match "red") {$localEvent.status = "red"}
  elseif ($report.Status -match "yellow") {$localEvent.status = "yellow"}
  elseif ($report.Status -match "grey") {$localEvent.status = "grey"}
  else {$localEvent.status = "green"}
  $localEvent.descriptionDetails = ($report | ConvertTo-Json)
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
