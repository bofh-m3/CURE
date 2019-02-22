  function Set-Detector {
    [CmdletBinding()]
    param
    (
      [Parameter(
        Position = 2,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Refresh dector info seconds')]
      [int]$refreshRate,
  
      [Parameter(
        Position = 3,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Infromation on where the dector is executed')]
      [string]$detectorEnvironment,

      [Parameter(
        Position = 4,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Timeout in seconds for when the detector is to be considered dead')]
      [int]$heartbeatTimeOut,

      [Parameter(
        Position = 5,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Area of Responsibility for this detector')]
        [ValidateSet("cost","helpdesk","process","azure","soc","cdc","software","no","fi","se","dk","remote","other")]
      [string]$area,

      [Parameter(
        Position = 6,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='How long a snooze is active in seconds')]
      [int]$snoozeTime,
 
      [Parameter(
        Position = 7,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Activate or deactivate detector')]
        [ValidateSet("True","False")]
      [string]$isActive,

      [Parameter(
        Position = 8,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Set a new name')]
      [string]$newName

    )
    
    DynamicParam 
    {
      $ParameterName = 'name'
      $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
      $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
      $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
      $ParameterAttribute.Mandatory = $True
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

      <# get current settings from database #>
      $currentSettings = Get-ODBCData -query "SELECT * FROM $inventoryTable WHERE (detectorName = '$name')"
      $detectorId = $currentSettings.detectorid
    }
  
    process
    {
      <# set all variables that are not specified #>
      if (!($refreshRate)) {$refreshRate = $currentSettings.refreshrate}
      if (!($detectorEnvironment)) {$detectorEnvironment = $currentSettings.detectorenvironment}
      if (!($heartbeatTimeOut)) {$heartbeatTimeOut = $currentSettings.heartbeattimeout}
      if (!($snoozeTime)) {$snoozeTime = $currentSettings.snoozetime}
      if (!($area)) {$area = $currentSettings.area}
      if (!($isActive)) 
      {
        if ($currentSettings.isactive -eq 0) {$isActive = 'False'}
        else {$isActive = 'True'}
      }
      if (!($newName)) {$newName = $name}

      <# write settings to database #>
      Set-ODBCData -query "UPDATE $inventoryTable SET refreshRate = $refreshRate, detectorEnvironment = '$detectorEnvironment', heartbeatTimeOut = $heartbeatTimeOut, snoozeTime = $snoozeTime, area = '$area', isActive = $isActive, detectorName = '$newName' WHERE detectorId = $detectorId"
    
      <# write event if Detector is marked as active #>
      If ($isActive -like $true)
      {
        $LocalEvent = @{
          detectorID = $detectorId;
          status = "green";
          eventShort = "Detector $newName has updated and is active.";
          contentType = "Text";
          descriptionDetails = "Detector $newName has updated and is active. The changes was made on $env:COMPUTERNAME by $env:USERNAME at $(get-date -Format 'yyyy-MM-dd HH:mm')"
        }
        Write-Event -LocalEvent $LocalEvent
      }
    }
  }
  