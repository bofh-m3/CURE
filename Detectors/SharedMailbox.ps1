$rootPath = "E:\CURE"

########################### LOAD MODULES AND SETTINGS ##############################
(cat -path $rootPath\globalSettings.ini | out-string) | iex
Import-Module $rootPath\modules\Credential.psm1
Import-Module $rootPath\modules\CURE.psm1
Import-Module $rootPath\modules\ODBC.psm1
Import-Module $rootPath\modules\Detector.psm1

################### LOCAL SETTINGS, FUNCTIONS AND DEPENDENCIES #####################
$detectorName = "Shared Mailbox"
$mailbox = "mailbox@company.fqdn"
$yellowDays = 2
$redDays = 5
$currentDate = (get-date)
Add-Type -Path "$rootPath\modules\Exchange\Web Services\2.2\Microsoft.Exchange.WebServices.dll"
function Get-UnreadMail {
  [CmdletBinding()]
  param ($MailboxName,[object]$Credential)
  $s = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService -ArgumentList Exchange2010_SP1
  $s.Credentials = New-Object Microsoft.Exchange.WebServices.Data.WebCredentials -ArgumentList $Credential.UserName, $Credential.GetNetworkCredential().Password
  $s.Url = new-object Uri("https://outlook.office365.com/EWS/Exchange.asmx");
  $folderid= new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox,$MailboxName) 
  $inbox = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($s,$folderid)
  $fv = new-object Microsoft.Exchange.WebServices.Data.FolderView(2000)
  $fv.Traversal = "Deep"
  $ffname = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+ContainsSubstring([Microsoft.Exchange.WebServices.Data.FolderSchema]::DisplayName,"Completed Items")
  $folders = $s.findFolders([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::MsgFolderRoot,$ffname, $fv)
  $completedfolder = $folders.Folders[0]
  $iv = new-object Microsoft.Exchange.WebServices.Data.ItemView(2000)
  $inboxfilter = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+SearchFilterCollection([Microsoft.Exchange.WebServices.Data.LogicalOperator]::And)
  $ifisread = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo([Microsoft.Exchange.WebServices.Data.EmailMessageSchema]::IsRead,$false)
  $inboxfilter.add($ifisread)
  $msgs = $s.FindItems($inbox.Id, $inboxfilter, $iv)
  if ($msgs.items)
  {
    $psPropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
    $psPropertySet.RequestedBodyType = [Microsoft.Exchange.WebServices.Data.BodyType]::Text;
    $s.LoadPropertiesForItems($msgs,$psPropertySet) | out-null
    $result=@()
    foreach ($msg in $msgs.items)
    {
      $cobj= "" | select @{n="Sender";e={$msg.From.ToString()}},@{n="Subject";e={$msg.subject.ToString()}},@{n="Body";e={$msg.body.text.ToString()}},@{n="Received";e={$msg.DateTimeReceived}},@{n="Status";e={$null}}
      $result += $cobj
    }
    return $result
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
try {$unreadMail = Get-UnreadMail -MailboxName $mailbox -Credential (Receive-Credential -SavedCredential $mailbox) -EA stop -WA silentlycontinue}
catch {
  $localEvent.descriptionDetails = $_
  $localEvent.status = 'grey'
  $localEvent.eventShort = "Unable to connect to $mailbox"
  $Disconnected = $True
}

################################### ANALYZE ########################################
<# this is custom #>
If (!$Disconnected)
{
  If ($unreadMail)
  {
    $report = @()
    ForEach ($m in $unreadMail)
    {
      if ($m.Received -lt $currentDate.AddDays(-$redDays)) {$m.Status = "red"}
      elseif ($m.Received -lt $currentDate.AddDays(-$yellowDays)) {$m.Status = "yellow"}
      else {$m.Status = "green"}
      if ($m.Subject.ToCharArray().count -gt 50) {$currentSubject = $m.Subject.Substring(0,47)+'...'}
      else {$currentSubject = $m.Subject.ToString()}
      if ($m.Body.ToCharArray().count -gt 200) {$currentBody = $m.Body.Substring(0,197)+'...'}
      else {$currentBody = $m.Body.ToString()}
      $report += "" | select `
       @{n="Sender";e={$m.Sender.ToString()}},`
       @{n="Subject";e={$currentSubject}},`
       @{n="Body";e={$currentBody}},`
       @{n="Received";e={$m.Received.ToString()}},`
       @{n="Status";e={$m.Status}}
    }
    $noRed = Get-ItemCount ($report | where {$_.status -like "red"})
    $noYellow = Get-ItemCount ($report | where {$_.status -like "yellow"})
    $noGreen = Get-ItemCount ($report | where {$_.status -like "green"})
    if ($noRed -gt 0) {$localEvent.status = "red"}
    ElseIf ($noYellow -gt 0) {$localEvent.status = "yellow"}
    Else {$localEvent.status = "green"}
    $localEvent.eventShort = "$noRed unread mail older than $redDays days, $noYellow unread mail older than $yellowDays days, $noGreen new mail"
    $localEvent.descriptionDetails = ($report | ConvertTo-Json)
    $localEvent.contentType = "json"
  }
  else 
  {
    $localEvent.descriptionDetails = "No unread mail in $mailbox"
    $localEvent.status = 'green'
    $localEvent.eventShort = "No unread mail in $mailbox"
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
