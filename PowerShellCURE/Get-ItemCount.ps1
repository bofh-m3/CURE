function Get-ItemCount {
  [CmdletBinding()]
  param
  (
    [Parameter(
      Position = 1,
      Mandatory = $True,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='Input object array to count items')]
      [AllowNull()]
    $Object
)
  $count = $Object.count
  if (($Object) -and ([string]::IsNullOrEmpty($count))) {Return 1}
  else {Return $count}
}