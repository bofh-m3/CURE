$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "Password Reminder"
$sqlServer = "MySQLServer.fqdn"
$sqlDb = "MyDB"
$sqlTable = "MyTable"
$logHistoryDays = 30
$hoursLastRunRed = 60
$hoursLastRunYellow = 40
$ignoreEmails = @("some.user1@somewhere","some.user2@company","some.user3@company")
function Connect-SQL {
  [CmdletBinding()]
  param ([string]$Server,[string]$Database)
  if ($SQLDefaultConnection) {$SQLDefaultConnection.Dispose()}
  $global:SQLDefaultConnection=New-Object System.Data.SqlClient.SQLConnection
  $SQLDefaultConnection.ConnectionString="Server=$Server;Database=$Database;Integrated Security=True;"
}
function Invoke-SQL {
  [CmdletBinding()]
  param ([string]$Query,[object]$Connection,[string]$SurpessExceptionString)
  if (!$Connection) 
  {
    if (!$SQLDefaultConnection) {Connect-SQL}
    $Connection=$SQLDefaultConnection
  }
  if (!$SurpessExceptionString) {$SurpessExceptionString="\*"}
  if ($Connection.state -notlike "open") {$Connection.Open()}
  $Command=$Connection.CreateCommand()
  $Command.CommandText=$Query
  try {$Result=$Command.ExecuteReader()}
  catch 
  {
    if ($_ -notmatch $SurpessExceptionString)
    {
      write-error $_
    }
    $Connection.Close()
  }
  if ($Result)
  {
    $Table = new-object "System.Data.DataTable"
    $Table.Load($Result)
    $Connection.Close()
    return $Table
  }
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
try {Connect-SQL -Server $sqlServer -Database $sqlDb -ea stop}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to $passwordremindersqlsrvr"
  $Disconnected = $True
}

If (!$Disconnected)
{
  try {$latestBatch = Invoke-SQL -Query "declare @latest_id int; select @latest_id=MAX(batch_id) from $sqlTable; select batch_id from $sqlTable where batch_id=@latest_id" -ea stop}
  catch {
    $localEvent.descriptionDetails = $_
    $localEvent.status = 'grey'
    $localEvent.eventShort = "Unable to collect data from db $sqlDb table $sqlTable"
    $Uncollected = $True
  }
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected -and !$Uncollected)
{
  $startBatch = ($latestBatch[0].batch_id - $logHistoryDays)
  $endBatch = $latestBatch[0].batch_id

  $log = Invoke-SQL -Query "select * from $sqlTable where batch_id BETWEEN $startBatch AND $endBatch"

  $report = $log | where {$_.type -notmatch "BatchStart|BatchEnd"} | sort batch_id,date -descending | select `
    @{n="date";e={$_.date.ToString()}},`
    @{n="batch_id";e={$_.batch_id}},`
    @{n="type";e={$_.type}},`
    @{n="EmailAddress";e={$_.EmailAddress}},`
    @{n="Name";e={$_.Name}},`
    @{n="OU";e={$_.OU}},`
    @{n="outlook_notified";e={$_.outlook_notified}},`
    @{n="slack_notified";e={$_.slack_notified}},`
    @{n="state";e={$_.status}},`
    @{n="message";e={$_.message}},`
    @{n="acknowledged";e={$_.acknowledged}},`
    @{n="status";e={$null}},`
    @{n="ignore";e={$false}}

  $latestRun = ($log.date | sort -Descending | select -Index 0)
  $hoursSinceLastRun = ((get-Date) - $latestRun).totalhours

  foreach ($i in $report)
  {
    if (![string]::IsNullOrEmpty($i.acknowledged)) {$i.status = "green"}
    else
    {
      if ([string]::IsNullOrEmpty($i.acknowledged)) {$i.acknowledged = $false}
      if ($i.state -like "Error") {$i.status = "red"}
      elseif (($i.EmailAddress -in $ignoreEmails) -and ($i.state -like "warning")) {$i.status = "green"; $i.ignore = $true}
      elseif ($i.state -like "Warning") {$i.status = "yellow"}
      elseif (($i.state -like "Success") -or ($i.state -like "Info")) {$i.status = "green"}
      else {$i.status = "grey"}
    }
  }

  $noRed = Get-ItemCount ($report | where {$_.status -like "red"})
  $noYellow = Get-ItemCount ($report | where {$_.status -like "yellow"})
  $noGreen = Get-ItemCount ($report | where {$_.status -like "green"})
  $noGrey = Get-ItemCount ($report | where {$_.status -like "grey"})

  $localEvent.eventShort = "$noRed red events, $noYellow yellow events, $noGreen green events, $noGrey grey events, $($latestRun.ToString())"

  if (($noRed -gt 0) -or ($hoursSinceLastRun -gt $hoursLastRunRed)) {$localEvent.status = "red"}
  elseif (($noYellow -gt 0) -or ($hoursSinceLastRun -gt $hoursLastRunYellow)) {$localEvent.status = "yellow"}
  elseif ($noGrey -gt 0) {$localEvent.status = "grey"}
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

