$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "PWM Health"
$url = "https://myPWMServer.fqdn/pwm/public/rest"
$daysRed = 0.2
$daysYellow = 0.1
$ignoreConfigAlerts = @(
  "User Permission configuration for setting Modules ⇨ Authenticated ⇨ Guest Registration ⇨ Guest Admin Permission issue: groupDN: DN '' is invalid.  This may cause unexpected issues."
  "Some other config error i want to supress"
)
function Get-PWMHealth {
  [CmdletBinding()]
  param ([string]$BaseURL)
  $header=@{"Content-Type"="application/json"}
  $curl=$BaseURL+'/health'
  $health=invoke-restmethod $curl -headers $header
  if ($health.error) {throw "$($health.errorCode) $($health.errorMessage)"}
  return $health.data
}
function Get-PWMStatistics {
  [CmdletBinding()]
  param ([int]$Days,[string]$statKey,[string]$statName,[string]$BaseURL)
  $header=@{"Accept"="application/json"}
  $body=@{}
  if ($Days) {$body.days=$Days}
  if ($statKey) {$body.statKey=$statKey}
  if ($statName) {$body.statName=$statName}
  $curl=$BaseURL+'/statistics'
  $stats=invoke-restmethod $curl -headers $header -body $body -ea stop
  if ($stats.error) {throw "$($stats.errorCode) $($stats.errorMessage)"}
  return $stats.data.eps
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
try {$health = Get-PWMHealth -BaseURL $url -EA stop}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to $url"
  $Disconnected = $True
}
try {$stats = Get-PWMStatistics -BaseURL $url -EA stop}
catch {
  $localEvent.descriptionDetails += $_
  $localEvent.status = 'grey'
  $localEvent.eventShort += "Unable to connect to $url"
  $Disconnected = $True
}


################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected)
{
  $report = $health.records | select @{n="state";e={$_.status}},`
   topic,detail,@{n="status";e={$null}},@{n="ignore";e={$false}},@{n="severity";e={$null}}
  if ([int]$stats.INTRUDER_ATTEMPTS_DAY -ge $daysRed) {$intrusion = "WARN"}
  elseif ([int]$stats.INTRUDER_ATTEMPTS_DAY -ge $daysYellow) {$intrusion = "CAUTION"}
  elseif ([int]$stats.INTRUDER_ATTEMPTS_DAY -eq 0) {$intrusion = "GOOD"}
  else {$intrusion = "UNKNOWN"}

  $report += "" | select @{n="state";e={$intrusion}},`
   @{n="topic";e={"Intrusion"}},`
   @{n="detail";e={"INTRUDER_ATTEMPTS_DAY: $($stats.INTRUDER_ATTEMPTS_DAY)"}},`
   @{n="status";e={$null}},`
   @{n="ignore";e={$false}},`
   @{n="severity";e={$null}}

  foreach ($i in $report)
  {
    if (($ignoreConfigAlerts -contains $i.detail) -and ($i.state -like "CONFIG")) {$i.status="green";$i.ignore=$true; $i.severity=1}
    elseif ($i.state -like "WARN") {$i.status="red"; $i.severity=2}
    elseif (($i.state -like "CAUTION") -or ($i.state -like "CONFIG")) {$i.status="yellow"; $i.severity=1}
    elseif ($i.state -like "GOOD") {$i.status="green"; $i.severity=0}
    else {$i.status="grey"; $i.severity=4}   
  }

  $noRed = Get-ItemCount ($report | where {$_.status-like "red"})
  $noYellow = Get-ItemCount ($report | where {$_.status-like "yellow"})
  $noGreen = Get-ItemCount ($report | where {$_.status-like "green"})
  $noGrey = Get-ItemCount ($report | where {$_.status-like "grey"})
  $localEvent.eventShort = "$noRed Red alarts, $noYellow Yellow alerts, $noGreen Green alerts"
  if ($report.Status -match "red") {$localEvent.status = "red"}
  elseif ($report.Status -match "yellow") {$localEvent.status = "yellow"}
  elseif ($report.Status -match "grey") {$localEvent.status = "grey"; $localEvent.eventShort += ", $noGrey Grey alarts"}
  else {$localEvent.status = "green"}
  $localEvent.descriptionDetails = ($report | sort severity -Descending | ConvertTo-Json)
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
