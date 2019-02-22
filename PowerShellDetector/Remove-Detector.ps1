  function Remove-Detector {
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
      $settings = Get-Detector -name $name
      $events = Get-DetectorEvents -name $name
      Set-ODBCData -query "DELETE FROM $eventDescriptionTable WHERE eventID IN ($($events.eventid -join ','))"
      Set-ODBCData -query "DELETE FROM $eventTable WHERE detectorId = $($settings.detectorId)"
      Set-ODBCData -query "DELETE FROM $inventoryTable WHERE detectorName = '$name'"
    }
  }
  