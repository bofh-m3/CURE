function Save-Credential {
  [CmdletBinding()]
  param 
  (
    [Parameter(
      Position=1,
      Mandatory=$True,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='UserName (or name) of the credential to save')]
    [string]$Name,

    [Parameter(
      Position=2,
      Mandatory=$False,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='UserName (or name) of the credential to save')]
    [string]$Password
  )

  process
  {
    $CredFile=$Name -replace '\\','�'
    $CredPath="$env:USERPROFILE\Credentials"
    if (!(test-path $CredPath)) {new-item $CredPath -itemtype directory | out-null}
    if ($Password) {convertto-securestring $Password -asplaintext -force | ConvertFrom-SecureString | out-file $CredPath\$CredFile -force}
    else {Read-Host "Enter Password for $Name" -AsSecureString | ConvertFrom-SecureString | Out-File $CredPath\$CredFile -force}
  }
}
