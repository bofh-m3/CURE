$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "3Par"
Import-Module $rootPath\modules\SSH-Sessions\SSH-Sessions.psm1
Add-Type -Path $rootPath\modules\SSH-Sessions\Renci.SshNet.dll
$username = "username"
$hosts = @("3par1.fqdn","3par2.fqdn")
$knownStatuses = @("Critical","Major","Degraded","Minor","Informational")
function Get-AlertObject {
  param (
      $ihost = $chost,
      $state = $null,
      $time = $(get-date -format 'yyyy-MM-dd HH:mm'),
      $severity = $null,
      $message = $null
    )
  $alertobject = "" | select `
  @{n="Host";e={$ihost}},`
  @{n="State";e={$state}},`
  @{n="Time";e={$time}},`
  @{n="Severity";e={$severity}},`
  @{n="Message";e={$message}}
  Return $alertobject
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
$alerts = @()
foreach ($chost in $hosts)
{
  $connect = $null
  $collect = $null
  <# connect #>
  try {$connect = New-SshSession -ComputerName $chost -Username $username -Password (Receive-Credential -SavedCredential $username -Type ClearText) -EA stop -WA stop}
  catch {
    $ErrMsg=$_
    $alerts += Get-AlertObject -state "ConnectionError" -severity "Critical" -message  $ErrMsg
    Continue
  }
  If ($connect -notlike "Successfully connected to $chost")
  {
    $alerts += Get-AlertObject -state "ConnectionError" -severity "Critical" -message  $connect
    Continue
  }
  <# collect alerts #>
  try {$collect = Invoke-SshCommand -Command 'showalert -n' -ComputerName $chost -quiet -EA stop -WA stop}
  catch {
    $ErrMsg=$_
    $alerts += Get-AlertObject -state "CollectionError" -severity "Major" -message  $ErrMsg
    Continue
  }
  If (!$collect -match "alerts") 
  {
    $alerts += Get-AlertObject -state "CollectionError" -severity "Major" -message  $collect
    Continue
  }
  <# parse alerts and add to array#>
  If ($collect -match "no alerts")
  {
    $alerts += Get-AlertObject -state "Operational" -severity "Informational" -message  "no alerts"
  }
  else
  {
    $collect = $collect -split 'Id          :'
    $collect = $collect | where {![string]::IsNullOrEmpty($_)}
    foreach ($a in $collect)
    {
      $a = ($a -split '[\r\n]') |? {$_}
      $cstate = ($a | select -index 1) -replace "State       : ",""
      $cdate = ($a | select -index 3) -replace "Time        : ",""
      $cseverity = ($a | select -index 4) -replace "Severity    : ",""
      $ctype = ($a | select -index 5) -replace "Type        : ",""
      $alerts += Get-AlertObject -state $cstate -time $cdate -severity $cseverity -message $ctype
    }
  }
}

################################### ANALYZE ########################################
<# this is custom #>
if (!$alerts)
{
  $localEvent.descriptionDetails = "no result generated when connecting and collecting"
  $localEvent.status = 'grey'
  $localEvent.eventShort = "no result generated when connecting and collecting"
}
else
{
  $noCritical = Get-ItemCount ($alerts | where {$_.Severity -like "Critical"})
  $noMajor = Get-ItemCount ($alerts | where {($_.Severity -like "Major")})
  $noDegraded = Get-ItemCount ($alerts | where {($_.Severity -like "Degraded")})
  $noMinor = Get-ItemCount ($alerts | where {($_.Severity -like "Minor")})
  $noInfo = Get-ItemCount ($alerts | where {($_.Severity -like "Informational")})
  $noUnknown = Get-ItemCount ($alerts | where {$_.Severity -notin $knownStatuses})
  $noNew = Get-ItemCount ($alerts | where {$_.state -like "New"})
  if (($noCritical -gt 0) -or ($noMajor -gt 0))
  {
    $localEvent.status = "red"
    $localEvent.eventShort = "$noCritical Critical alarms, $noMajor Major alarms"
  }
  elseif (($noDegraded -gt 0) -or ($noMinor -gt 0))
  {
    $localEvent.status = "yellow"
    $localEvent.eventShort = "$noDegraded Degraded alarms, $noMinor Minor alarms"
  }
  elseif ($noUnknown -gt 0)
  {
    $localEvent.status = "grey"
    $localEvent.eventShort = "$noUnknown Unknown alarms"
  }
  else
  {
    $localEvent.status = "green"
    $localEvent.eventShort = "$noInfo Informational alarms"
  }
  $localEvent.eventShort += ". $noNew new alarms"
  $localEvent.descriptionDetails = ($alerts | ConvertTo-Json)
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
