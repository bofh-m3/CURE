$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "Zoho Desk"
$token = Receive-Credential -SavedCredential MyAPIKey -Type ClearText
$orgid = "ORGID123"
$url = "https://desk.zoho.com/api/v1/tickets?status=new,in progress,on hold,escalated,open&limit=99"
$header = @{'Authorization' = $token; 'orgId' = $orgid}
$unansweredRed = 4
$unansweredYellow = 2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
try {$tickets = Invoke-RestMethod -Uri $url -Headers $header -Method GET -ContentType "application/json" -ea stop}
catch {
  $localEvent.descriptionDetails = $_.ToString() -replace "'"
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to Zoho"
  $Disconnected = $True
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected -and !$Uncollected)
{
  $report = $tickets.data | where {$_.statusType -like "open"} | select ticketNumber,email,subject,createdTime,@{n="state";e={$_.status}},threadCount,customerResponseTime,@{n="lastThreadDirection";e={$_.lastThread.direction}},@{n="noReplyHours";e={$null}},@{n="status";e={$null}}
  foreach ($i in $report)
  {
    if ($i.state -like "On Hold") {$i.status = "green"}
    elseif (($i.lastThreadDirection -like "in") -or ($i.state -like "new"))
    {
      if ($i.threadCount -gt 1)
      {
        $i.noReplyHours = Get-Workhours $i.customerResponseTime
      }
      else
      {
        $i.noReplyHours = Get-Workhours $i.createdTime
      }
      if ($i.noReplyHours -ge $unansweredRed) {$i.status = "red"}
      elseif ($i.noReplyHours -ge $unansweredYellow) {$i.status = "yellow"}
      else {$i.status = "green"}
    }
    elseif (!$i.lastThreadDirection) {$i.status = "grey"}
    else {$i.status = "green"}
  }
  [datetime]$latestupdate = ($tickets.data.createdTime | sort -Descending | select -Index 0)
  $noNew = Get-ItemCount ($tickets.data | where {$_.status -like "new"})
  $noOpen = Get-ItemCount ($tickets.data | where {$_.statusType -like "open"})
  $noRed = Get-ItemCount ($report | where {$_.status -like "red"})
  $noYellow = Get-ItemCount ($report | where {$_.status -like "yellow"})
  $noGrey = Get-ItemCount ($report | where {$_.status -like "grey"})
  if ($noRed -gt 0) {$localEvent.status = "red"}
  elseif ($noYellow -gt 0) {$localEvent.status = "yellow"}
  elseif ($noGrey -gt 0) {$localEvent.status = "grey"}
  else {$localEvent.status = "green"}
  $localEvent.eventShort = "$noNew new issues, $noRed urgent issues, $noYellow late issues, $noOpen open issues, $($latestupdate.ToString())"
  $localEvent.descriptionDetails = ($report | sort createdTime -Descending | ConvertTo-Json)
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
