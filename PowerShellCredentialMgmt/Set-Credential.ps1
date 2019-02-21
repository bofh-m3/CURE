function Set-Credential {
  [CmdletBinding()]
  param 
  (
  )

  DynamicParam 
  {
    $ParameterName = 'SavedCredential'
    $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $ParameterAttribute.Mandatory = $False
    $ParameterAttribute.Position = 1
    $AttributeCollection.Add($ParameterAttribute)

    #----  Generate and set the ValidateSet ----#
    $CredPath="$env:USERPROFILE\Credentials"
    try {$arrSet = ((ls $CredPath -ea stop | select -expand Name | sort) -replace '�','\')}
    catch {return}
    if (!$arrSet) {Return}
    #-------------------------------------------#

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)
    $AttributeCollection.Add($ValidateSetAttribute)
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
    return $RuntimeParameterDictionary
  }

  begin
  {
    [string]$SavedCredential = $PsBoundParameters[$ParameterName]
  }

  process
  {
    $CredFile=$SavedCredential -replace '\\','�'
    $CredPath="$env:USERPROFILE\Credentials"
    Read-Host "Enter New Password for $SavedCredential" -AsSecureString | ConvertFrom-SecureString | Out-File $CredPath\$CredFile -force
  }
}
