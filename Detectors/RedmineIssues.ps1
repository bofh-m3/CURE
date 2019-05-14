$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "Redmine Issues"
(cat -path $rootPath\modules\Get-RedmineIssue.ps1 | out-string) | iex
$projID = 123
$excludeIssues = @(123,456,789)
$itstaff = @("IT Staff1","IT Staff2","IT Staff3","IT Staff4")
$DefaultRedmineURI = "https://myredmine.fqdn"
$DefaultRedmineApiKey = "DefaultRedmineApiKey"
$noAnswerRedHours = 4
$noAnswerYellowHours = 2
$noAnswerFollowUpRedHours = 70
$noAnswerFollowUpYellowHours = 35

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
try {$issues = Get-RedmineIssue -Filter -ProjectID 598 -EA stop -WA silentlycontinue}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to $DefaultRedmineURI"
  $Disconnected = $True
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected)
{
  $report = $issues | where {$_.id -notin $excludeIssues} | select id,subject,`
    @{n="author";e={$_.author.name}},`
    @{n="state";e={$_.status.name}},`
    @{n="category";e={$_.category.name}},`
    @{n="latest_answer_by";e={((Get-RedmineIssue -ID $_.id -Include journals).journals | sort created_on -Descending | select -Index 0).user.name}},`
    created_on,updated_on,`
    @{n="unanswered_hours";e={$null}},`
    @{n="status";e={$null}}
  foreach ($i in $report)
  {
    $i.unanswered_hours =  Get-Workhours $i.updated_on
    if ($i.category -like "Follow-up")
    {
      if ($i.unanswered_hours -gt $noAnswerFollowUpRedHours) {$i.status = "red"}
      elseif ($i.unanswered_hours -gt $noAnswerFollowUpYellowHours) {$i.status = "yellow"}
      else {$i.status = "green"}
    }
    elseif (($i.latest_answer_by -notin $itstaff) -and ($i.state -notlike "Resolved"))
    {
      if ($i.unanswered_hours -gt $noAnswerRedHours) {$i.status = "red"}
      elseif ($i.unanswered_hours -gt $noAnswerYellowHours) {$i.status = "yellow"}
      else {$i.status = "green"}
    }
    else {$i.status = "green"}
  }
  [datetime]$latestupdate = ($report.updated_on | sort -Descending | select -Index 0)
  $noNew = Get-ItemCount ($report | where {$_.state -like "New"})
  $noRed = Get-ItemCount ($report | where {$_.status -like "Red"})
  $noYellow = Get-ItemCount ($report | where {$_.status -like "Yellow"})
  $noOpen = Get-ItemCount ($report | where {$_.state -notlike "Resolved"})
  if ($noRed -gt 0) {$localEvent.status = "red"}
  elseif ($noYellow -gt 0) {$localEvent.status = "yellow"}
  else {$localEvent.status = "green"}
  $localEvent.eventShort = "$noNew new issues, $noRed urgent issues, $noYellow late issues, $noOpen open issues, $($latestupdate.ToString())"
  $localEvent.descriptionDetails = ($report | sort status -Descending | ConvertTo-Json)
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
