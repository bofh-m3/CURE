function Get-DetectorSettings {
  [CmdletBinding()]
  param
  (
    [Parameter(
      Position = 1,
      Mandatory = $True,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='name of the detector')]
    [Object]$detectorName
)
  Get-ODBCData -query "SELECT * FROM $inventoryTable WHERE detectorName = '$detectorName'"
}
