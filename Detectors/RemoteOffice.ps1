$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "Remote Office"
$dhcpserver = "myDHCPserver.fqdn"
$ScopeId = "10.125.100.0"
$username = "myUser"
$LeaseExpiresHours = 24
$upYellow = 15
$upRed = 5
$latestLeaseYellowHours = 2
$latestLeaseRedHours = 6
$autoRebootFirewallEnabled = $true
$FirewallIP = "10.125.100.1"
$FirewallUser = "myFortiUser"
$postSlack = $true
$ITStafSlackIDs = @("ABC123","ABC456")
$SlackWebHook = "https://hooks.slack.com/services/XXX/YYY/ZZZ"
$SlackChannel = "#MyChannel"
$SlackBotName = "CURE"

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
try {$leases = Invoke-Command -ComputerName $dhcpserver -ScriptBlock {Get-DhcpServerv4Lease -ScopeId $ScopeId} -Credential (Receive-Credential -SavedCredential $username) -ea stop}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.contentType = "text"
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to $dhcpserver to collect active leases"
  $Disconnected = $True
}
If (!$Disconnected)
{
  $report = @()
  foreach ($l in $leases)
  {
    $report += $l | select @{n="Client";e={$l.HostName}},`
      @{n="IP";e={$l.IPAddress}},`
      @{n="LeaseExpires";e={$l.LeaseExpiryTime.ToString()}},`
      @{n="IsUp";e={(Test-Connection -ComputerName $l.IPAddress -Count 1 -Quiet)}}
  }
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected -and !$Uncollected)
{
  $IsUp = [math]::round((($report | where {$_.IsUp}).count / $report.count),2) * 100
  $latestLease = $leases.LeaseExpiryTime | sort -Descending | select -Index 0
  $latestLeaseHours = ((Get-Date) - $latestlease.AddHours(-$LeaseExpiresHours)).hours
  if (($IsUp -lt $upRed) -and ($latestLeaseHours -ge $latestLeaseRedHours)) {$localEvent.status = "red"}
  elseif (($IsUp -lt $upYellow) -and ($latestLeaseHours -ge $latestLeaseYellowHours)) {$localEvent.status = "yellow"}
  elseif (($IsUp -ge $upYellow) -or ($latestLeaseHours -lt $latestLeaseYellowHours)) {$localEvent.status = "green"}
  else {$localEvent.status = "grey"}
  $localEvent.eventShort = "$IsUp% of PCs responded, Latest DHCP-lease $latestLeaseHours hours ago."
  $localEvent.descriptionDetails = ($report | sort LeaseExpires -Descending | ConvertTo-Json)
  $localEvent.contentType = "json"
}

################# COMPARE WITH LAST EVENT AND WRITE NEW EVENT ######################
If (Test-IfNewEvent $LocalEvent)
{
  Write-Event $LocalEvent
  if ($IsUp -eq 0)
  {
    if ($postSlack)
    {
      $payload = @{
       "channel" = $SlackChannel;
       "username" = $SlackBotName;
       "text" = "$(($ITStafSlackIDs | %{'<@' + $_ + '>'}) -join ', ') Company Remote Office seem to be down";
       "icon_emoji" = ":skull:"
      }
      Invoke-RestMethod -Method Post -Uri $SlackWebHook -Body ($payload | ConvertTo-Json)
    }
    if ($autoRebootFirewallEnabled)
    {
      $payload.text = "Auto reboot firewall is enabled. Initiate reboot sequence in t minus 120 sec"
      Invoke-RestMethod -Method Post -Uri $SlackWebHook -Body ($payload | ConvertTo-Json)
      sleep -s 120
      import-module Posh-SSH
      New-SSHSession -ComputerName $FirewallIP -Credential (Receive-Credential -SavedCredential $FirewallUser) -AcceptKey
      $session = Get-SSHSession -Index 0
      $stream = $session.Session.CreateShellStream("reboot", 0, 0, 0, 0, 1000)
      $stream.Write("execute reboot comment CURE`n")
      $stream.Write("y`n")
      $resultReboot = $stream.Read()
      Remove-SSHSession -Index 0
      $payload.text = "Firewall result: $resultReboot"
      Invoke-RestMethod -Method Post -Uri $SlackWebHook -Body ($payload | ConvertTo-Json)
    }
  }
}

############################## WRITE HEARTBEAT #####################################
Write-HeartBeat $settings.detectorid

################################### CLEANUP ########################################
<# this is custom #>
