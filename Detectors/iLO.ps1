$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "iLO"
$hosts = @("MyiLOHost1.fqdn","MyiLOHost2.fqdn","MyiLOHost3.fqdn","MyiLOHost4.fqdn","MyiLOHost5.fqdn","MyiLOHost6.fqdn","MyiLOHost7.fqdn")
$user = "myUserName"
$logSources = @("/redfish/v1/Systems/1/LogServices/IML/Entries/")

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
$report = @()
$sessions = @()
foreach ($h in $hosts)
{
  $cError = $null
  $cSession = "" | select `
    @{n="Name";e={$h}},`
    @{n="Session";e={$null}},`
    @{n="Message";e={$null}},`
    @{n="Status";e={$null}}

  try {$cConnect = Connect-HPERedfish -Address $h -Username $user -Password (Receive-Credential -SavedCredential $user -Type ClearText) -DisableCertificateAuthentication -EA stop}
  catch {
    $cError = $_.ToString()
    $report += "" | select `
      @{n="Target";e={$h}},`
      @{n="Source";e={"Cure"}},`
      @{n="Id";e={$null}},`
      @{n="Created";e={(get-date -Format "yyyy-MM-dd HH:mm:ss")}},`
      @{n="Type";e={"Connect"}},`
      @{n="Message";e={$cError}},`
      @{n="State";e={"Error"}},`
      @{n="Status";e={"red"}}
  }

  if (!$cError)
  {
    if (($cConnect.RootUri -like "https://$h/redfish/v1/") -and (![string]::IsNullOrEmpty($cConnect.'X-Auth-Token')) -and ($cConnect.Location -like "https://$h/redfish/v1/SessionService/Sessions/$user*"))
    {
      $cSession.Session = $cConnect
      $cSession.Status = "green"
      $sessions += $cSession
    }
    else
    {
      $cSession.Message = "Unknown connection status"
      $cSession.Status = "grey"
    }
  }
}

if ($sessions.Status -match "green")
{
  foreach ($s in $sessions)
  {
    if ($s.status -like "green")
    {
      foreach ($url in $logSources)
      {
        try {$cEntries = Get-HPERedfishDataRaw -Odataid $url -Session $s.session -DisableCertificateAuthentication -EA stop}
        catch {
          $errMsg = $_
          $report += "" | select `
            @{n="Target";e={$s.Name}},`
            @{n="Source";e={"Cure"}},`
            @{n="Id";e={$null}},`
            @{n="Created";e={(get-date -Format "yyyy-MM-dd HH:mm:ss")}},`
            @{n="Type";e={"Collect"}},`
            @{n="Message";e={$errMsg}},`
            @{n="State";e={"Error"}},`
            @{n="Status";e={"red"}}
          Continue
        }
        foreach ($m in $cEntries.members)
        {
          try {$cEvent = Get-HPERedfishDataRaw -Odataid $m.'@odata.id' -Session $s.session -DisableCertificateAuthentication -EA stop}
          catch {
            $errMsg = $_
            $report += "" | select `
              @{n="Target";e={$s.Name}},`
              @{n="Source";e={($url -split '/')[-3]}},`
              @{n="Id";e={($m -split '/')[-2]}},`
              @{n="Created";e={(get-date -Format "yyyy-MM-dd HH:mm:ss")}},`
              @{n="Type";e={"Collect"}},`
              @{n="Message";e={$errMsg}},`
              @{n="State";e={"Error"}},`
              @{n="Status";e={"red"}}
            Continue
          }
          $report += "" | select `
            @{n="Target";e={$s.Name}},`
            @{n="Source";e={$cEvent.Name}},`
            @{n="Id";e={$cEvent.Id}},`
            @{n="Created";e={$cEvent.Created}},`
            @{n="Type";e={$cEvent.EntryType}},`
            @{n="Message";e={$cEvent.Message}},`
            @{n="State";e={$cEvent.Severity}},`
            @{n="Status";e={$null}}
        }
      }
    }

    else
    {
      $report += "" | select `
        @{n="Target";e={$s.Name}},`
        @{n="Source";e={"Cure"}},`
        @{n="Id";e={$null}},`
        @{n="Created";e={(get-date -Format "yyyy-MM-dd HH:mm:ss")}},`
        @{n="Type";e={"Collect"}},`
        @{n="Message";e={$errMsg}},`
        @{n="State";e={"Error"}},`
        @{n="Status";e={"red"}}
    }
  }
}

else
{
  $localEvent.descriptionDetails = $report | convertto-json
  $localEvent.contentType = "json"
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to any iLO hosts"
  $Uncollected = $True
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Uncollected)
{
  foreach ($i in $report)
  {
    if (!$i.status)
    {
      if ($i.state -match "Error|Critical") {$i.status = "red"}
      elseif ($i.state -match "Warning") {$i.status = "yellow"}
      elseif ($i.state -match "OK") {$i.status = "green"}
      else {$i.status = "grey"}
    }
  }
  [datetime]$latestupdate = ($report.created | sort -Descending | select -Index 0)
  $noRed = Get-ItemCount ($report | where {$_.Status -like "red"})
  $noYellow = Get-ItemCount ($report | where {$_.Status -like "yellow"})
  $noGreen = Get-ItemCount ($report | where {$_.Status -like "green"})
  $noGrey = Get-ItemCount ($report | where {$_.Status -notmatch "red|green|yellow"})
  $localEvent.eventShort = "$noRed Red alerts, $noYellow Yellow alerts, $nogreen Green alerts, $nogrey Grey alerts, $($latestupdate.ToString())"
  if ($noRed -gt 0) {$localEvent.status = "red"}
  elseif ($noYellow -gt 0) {$localEvent.status = "yellow"}
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
<# this is custom #>
