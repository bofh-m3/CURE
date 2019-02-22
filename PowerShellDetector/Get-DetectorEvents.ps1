function Get-DetectorEvents {
  [CmdletBinding()]
  param
  (
    [int]$numberOfEvents,
    [switch]$details
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
      $detectorId = Get-Detector -name $name | select -ExpandProperty detectorid
      If ($numberOfEvents)
      {
        $result = Get-ODBCData -query "SELECT * FROM $eventTable WHERE detectorId = $detectorId ORDER BY eventId DESC LIMIT $numberOfEvents"
      }
      else
      {
        $result = Get-ODBCData -query "SELECT * FROM $eventTable WHERE detectorId = $detectorId"
      }
    }
    else
    {
      If ($numberOfEvents)
      {
        $result = Get-ODBCData -query "SELECT * FROM $eventTable ORDER BY eventId DESC LIMIT $numberOfEvents"
      }
      else
      {
        $result = Get-ODBCData -query "SELECT * FROM $eventTable"
      }
    }
    if ($details)
    {
      $result | Add-Member -MemberType NoteProperty -Name descriptionDetails -Value $null
      foreach ($i in $result)
      {
        $i.descriptionDetails = (Get-ODBCData -query "SELECT descriptionDetails FROM $eventDescriptionTable WHERE eventId = $($i.eventid)" | select -ExpandProperty descriptionDetails)
      }
      Return $result
    }
    else {Return $result}
  }
}
