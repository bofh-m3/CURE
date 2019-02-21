function Convert-CredentialToBasic {
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
    if (![string]::IsNullOrEmpty($SavedCredential))
    {
      $CredFile=$SavedCredential -replace '\\','�'
      $CredPath="$env:USERPROFILE\Credentials"
      $passw=Get-Content $CredPath\$CredFile | ConvertTo-SecureString
      $bstr=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passw)
      $CredObject=[System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
      $bcred=[System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($SavedCredential):$($CredObject)"))
      return "basic $bcred"
    }
  }
}
