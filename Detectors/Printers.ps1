$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "Printers"
$printers = @{
  "Printer1.fqdn" = "MP C2003 - RICOH";
  "Printer2.fqdn" = "MP C2003Z - RICOH";
  "Printer3.fqdn" = "MP C2003 - RICOH";
  "Printer4.fqdn" = "MP C3003 - RICOH";
  "Printer5.fqdn" = "MP C306Z - RICOH"
}
$colors = @("black","cyan","magenta","yellow")
$remainingRed = 2
$remainingYellow = 15

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
foreach ($printer in $printers.keys)
{
  $HTML=$null
  $result = "" | select @{n="printer";e={$printer}},`
   @{n="status";e={"grey"}},`
   @{n="model";e={$($printers.$printer)}},`
   @{n="black";e={$null}},`
   @{n="cyan";e={$null}},`
   @{n="magenta";e={$null}},`
   @{n="yellow";e={$null}},`
   @{n="message";e={$null}}
  $uri = "http://$($printer)/web/guest/sv/websys/webArch/getStatus.cgi#linkToner"
  try {$HTML = Invoke-WebRequest $uri -EA stop}
  catch 
  {
    $result.message = $_.ToString()
    $result.status = "red"
  }
  if ($HTML)
  {
    $tonerHTML = $HTML.ParsedHtml.body.getElementsByTagName('div') | Where {$_.classname -eq 'tonerArea'} 
    $n = 0
    foreach ($i in $tonerHTML.innerHTML)
    {
      if ($n -eq 0) {[int]$result.black = ($i -split 'width=') -split ' height=' | select -Index 1}
      elseif ($n -eq 1) {[int]$result.cyan = ($i -split 'width=') -split ' height=' | select -Index 1}
      elseif ($n -eq 2) {[int]$result.magenta = ($i -split 'width=') -split ' height=' | select -Index 1}
      elseif ($n -eq 3) {[int]$result.yellow = ($i -split 'width=') -split ' height=' | select -Index 1}
      else {$result.message = "too many colors"}
     $n++
    }
  }
  $report += $result
}   

################################### ANALYZE ########################################
<# this is custom #>
foreach ($r in $report)
{
  $remaining = $colors | %{$r.$_}
  if ($remaining | where {$_ -lt $remainingRed}) {$r.status = "red"}
  elseif ($remaining | where {$_ -lt $remainingYellow}) {$r.status = "yellow"}
  else {$r.status = "green"}
}
$noRed = Get-ItemCount ($report | where {$_.status -like "red"})
$noYellow = Get-ItemCount ($report | where {($_.status -like "yellow")})
$noGreen = Get-ItemCount ($report | where {$_.status -like "green"})
if ($noRed -gt 0) {$localEvent.status = "red"}
elseif ($noYellow -gt 0) {$localEvent.status = "yellow"}
else {$localEvent.status = "green"}
$localEvent.eventShort = "$noRed replace now, $noYellow replace soon, $noGreen OK"
$localEvent.descriptionDetails = ($report | ConvertTo-Json)
$localEvent.contentType = "json"

################# COMPARE WITH LAST EVENT AND WRITE NEW EVENT ######################
If (Test-IfNewEvent $LocalEvent)
{
  Write-Event $LocalEvent
}

############################## WRITE HEARTBEAT #####################################
Write-HeartBeat $settings.detectorid

################################### CLEANUP ########################################
<# this is custom #>
