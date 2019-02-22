function Get-Detector {
  [CmdletBinding()]
  param
  (
  )
  
  DynamicParam 
  {
    $ParameterName = 'name'
    $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $ParameterAttribute.Mandatory = $False
    $ParameterAttribute.Position = 1
    $AttributeCollection.Add($ParameterAttribute)

    #----  Generate and set the ValidateSet ----#
    $arrSet = ((Get-ODBCData -query "SELECT detectorName from $inventoryTable") | select -expand detectorName | sort)
    #-------------------------------------------#

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)
    $AttributeCollection.Add($ValidateSetAttribute)
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string[]], $AttributeCollection)
    $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
    return $RuntimeParameterDictionary
  }

  begin
  {
    <# bind dynamic parameter #>
    [string]$name = $PsBoundParameters[$ParameterName]
  }

  process
  {
    <# Collect and return data #>
    if ($name)
    {
      Get-ODBCData -query "SELECT * FROM $inventoryTable WHERE detectorName = '$name'"
    }
    else
    {
      Get-ODBCData -query "SELECT * FROM $inventoryTable"
    }
  }
}
