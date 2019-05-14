$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "Zendesk"
$user = "myUserName/token"
$apikey = (Receive-Credential -SavedCredential "MyAPIKey" -Type ClearText)
$cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$apikey)))
$baseurl = "https://myInstance.zendesk.com/api/v2/"
$unansweredRed = 4
$unansweredYellow = 2
function Get-RequesterName {
  param ($id)
  return ($users | where {$_.id -eq $id}).name
}
function Get-ZendeskData {
  [CmdletBinding()]
  param ($endpoint)
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $result=@()
  $fetch = Invoke-RestMethod -Headers @{Authorization=("Basic {0}" -f $cred)} -Uri "$baseurl$endpoint.json" -Method Get -ContentType "application/json"
  $result += $fetch.$endpoint
  while (![string]::IsNullOrEmpty($fetch.next_page))
  {
    $url=$fetch.next_page
    $fetch = Invoke-RestMethod -Headers @{Authorization=("Basic {0}" -f $cred)} -Uri $url -Method Get -ContentType "application/json"
    $result+=$fetch.$endpoint
  }
  return $result
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
try {$users = Get-ZendeskData -endpoint users -EA stop}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to $baseurl"
  $Disconnected = $True
}
If (!$Disconnected)
{
  try {$tickets = Get-ZendeskData -endpoint tickets -EA stop}
  catch {
    $localEvent.descriptionDetails = $_
    $localEvent.status = 'grey'
    $localEvent.eventShort = "Unable to connect to $baseurl"
    $Uncollected = $True
  }
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected -and !$Uncollected)
{
  $report = $tickets | where {$_.status -notlike "closed"} | select id,subject,`
    @{n="requester";e={(Get-RequesterName $_.requester_id)}}, `
    @{n="assignee";e={(Get-RequesterName $_.assignee_id)}}, `
    @{n="state";e={$_.status}}, `
    @{n="tags";e={$_.tags -join ','}}, `
    created_at,updated_at, `
    @{n="noanswer_hours";e={(Get-Workhours $_.updated_at)}},`
    @{n="status";e={$null}}
  
  foreach ($t in $report)
  {
    if (($t.noanswer_hours -gt $unansweredRed) -and ($t.state -like "new")) {$t.status = "red"}
    elseif (($t.noanswer_hours -gt $unansweredYellow) -and ($t.state -like "new")) {$t.status = "yellow"}
    else {$t.status = "green"}
  }
  [datetime]$latestupdate = ($tickets.updated_at | sort -Descending | select -Index 0)
  $noNew = Get-ItemCount ($report | where {$_.state -like "new"})
  $noRed = Get-ItemCount ($report | where {$_.status -like "red"})
  $noYellow = Get-ItemCount ($report | where {$_.status -like "yellow"})
  $noOpen = Get-ItemCount ($report | where {$_.state -notlike "solved"})
  if ($noRed -gt 0) {$localEvent.status = "red"}
  elseif ($noYellow -gt 0) {$localEvent.status = "yellow"}
  else {$localEvent.status = "green"}
  $localEvent.eventShort = "$noNew new issues, $noRed urgent issues, $noYellow late issues, $noOpen open issues, $($latestupdate.ToString())"
  $localEvent.descriptionDetails = ($report | sort status,noanswer_hours -Descending | ConvertTo-Json)
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
