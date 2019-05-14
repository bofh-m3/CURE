$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "O365 Health"
$greenAlerts = @("FalsePositive","ServiceRestored","ServiceOperational","Service restored","False positive","Service operational")
$redSeverity = @("Critical","High","Sev0","Sev1")
$forceGreen = @("SomeIssueIDtoSupress1","SomeIssueIDtoSupress2","SomeIssueIDtoSupress3")
$ClientSecret = Receive-Credential -SavedCredential "MyO365Secret" -Type ClearText
$ClientID = "MyClientIDGUID"
$tenantdomain = "MyO365tenant"
function Get-O365Health {
  [CmdletBinding()]
  param ([Switch]$AllMessages,[string]$ID),[String]$ClientSecret,[string]$ClientID,[string]$tenantdomain)
  begin
  {
    $body = @{grant_type="client_credentials";resource="https://manage.office.com";client_id=$ClientID;client_secret=$ClientSecret}
    $oauth = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($tenantdomain)/oauth2/token?api-version=1.0" -Body $body
    $headerParams = @{'Authorization'="$($oauth.token_type) $($oauth.access_token)"}
  }
  process
  {
    if ($AllMessages)
    {
      Return (Invoke-RestMethod -Uri "https://manage.office.com/api/v1.0/$($tenantdomain)/ServiceComms/Messages" -Headers $headerParams -Method Get)
    }
    elseif ($ID)
    {
      Return (Invoke-RestMethod -Uri "https://manage.office.com/api/v1.0/$($tenantdomain)/ServiceComms/Messages?ID=$ID" -Headers $headerParams -Method Get)
    }
    else
    {
      Return (Invoke-RestMethod -Uri "https://manage.office.com/api/v1.0/$($tenantdomain)/ServiceComms/CurrentStatus" -Headers $headerParams -Method Get)
    }
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
try {$status = Get-O365Health -ClientSecret $ClientSecret -ClientID $ClientID -tenantdomain $tenantdomain -EA stop -WA silentlycontinue}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to O365 Health API"
  $Disconnected = $True
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected)
{
  $incidents = $status.value | where {$_.status -notin $greenAlerts}
  if (!$incidents)
  {
    $localEvent.status = 'green'
    $localEvent.eventShort = "$(Get-ItemCount $status.value) services OK"
  }
  else
  {
    $report = @()
    $messages = Get-O365Health -AllMessages -ClientSecret $ClientSecret -ClientID $ClientID -tenantdomain $tenantdomain
    foreach ($i in $incidents.IncidentIds)
    {
      $report += ($messages.value | where {$_.id -eq $i}) | select `
        @{n="Id";e={$_.id}},`
        @{n="Title";e={$_.Title}},`
        @{n="State";e={$_.Status}},`
        @{n="Workload";e={$_.Workload}},`
        @{n="ActionType";e={$_.ActionType}},`
        @{n="Classification";e={$_.Classification}},`
        @{n="Feature";e={$_.Feature}},`
        @{n="ImpactDescription";e={$_.ImpactDescription}},`
        @{n="LastUpdatedTime";e={([datetime]$_.LastUpdatedTime).ToString()}},`
        @{n="StartTime";e={([datetime]$_.StartTime).ToString()}},`
        @{n="Severity";e={$_.Severity}},`
        @{n="Status";e={$null}}
    }
    foreach ($e in $report)
    {
      if (($e.Id -in $forceGreen) -or ($e.State -in $greenAlerts)) {$e.status = "green"}
      elseif ($e.Severity -in $redSeverity) {$e.status = "red"}
      else {$e.status = "yellow"}
    }
    $localEvent.descriptionDetails = ($report | sort status | ConvertTo-Json)
    $localEvent.contentType = "json"
    if ($report.status -contains "red") {$localEvent.status = "red"}
    elseif ($report.status -notcontains "yellow") {$localEvent.status = "green"}
    else {$localEvent.status = "yellow"}
    if ((($report | where {$_.status -notlike "green"}).Workload | select -Unique).count -le 4) {$localEvent.eventShort = "$((($report | where {$_.status -notlike "green"}).Workload | select -Unique) -join ', ')"}
    else {$localEvent.eventShort = "$((($report | where {$_.status -notlike "green"}).Workload | select -Unique).count) Workloads with issues"}
    if ($report.count -eq 1) {$localEvent.eventShort = "$($report.workload), $($report.LastUpdatedTime)"}
    else {$localEvent.eventShort += ", $(($report.LastUpdatedTime | sort -descending)[0])"}
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
