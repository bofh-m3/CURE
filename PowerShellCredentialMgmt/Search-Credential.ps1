function Search-Credential {
  [CmdletBinding()]
  param 
  (
    [Parameter(
      Position=1,
      Mandatory=$False,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='UserName (or name) of the credential to save')]
    [string]$Name
  )

  process
  {
    $CredFile='*'+($Name -replace '\\','�')+'*'
    $CredPath="$env:USERPROFILE\Credentials"
    (ls $CredPath\$CredFile | select -expand Name) -replace '�','\'
  }
}
