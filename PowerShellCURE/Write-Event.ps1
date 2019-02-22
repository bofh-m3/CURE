function Write-Event {
  [CmdletBinding()]
  param
  (
    [Parameter(
      Position = 1,
      Mandatory = $True,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='Local Event generated by detector')]
    [Object]$LocalEvent
)
  Set-ODBCData -query "INSERT INTO $eventTable (detectorID, dateTime, status, eventShort) VALUES ($($LocalEvent.detectorId), now(), '$($LocalEvent.status)', '$($LocalEvent.eventShort)')"
  $CurrentEventId = Get-ODBCData -query "SELECT eventId FROM $eventTable WHERE detectorId = $($LocalEvent.detectorId) ORDER BY eventId DESC LIMIT 1" | select -ExpandProperty eventId
  Set-ODBCData -query "INSERT INTO $eventDescriptionTable (eventId, contentType, descriptionDetails) VALUES ($CurrentEventId, '$($LocalEvent.contentType)', '$($LocalEvent.descriptionDetails)')"
}