function New-Detector {
    [CmdletBinding()]
    param
    (
      [Parameter(
        Position = 1,
        Mandatory = $True,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='name of Detector')]
      [string]$name,
  
      [Parameter(
        Position = 2,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Refresh dector info seconds')]
      [int]$refreshRate = 60,
  
      [Parameter(
        Position = 3,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Infromation on where the dector is executed')]
      [string]$detectorEnvironment = $env:COMPUTERNAME,

      [Parameter(
        Position = 4,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Timeout in seconds for when the detector is to be considered dead')]
      [int]$heartbeatTimeOut = 3600,

      [Parameter(
        Position = 5,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Area of Responsibility for this detector')]
        [ValidateSet("cost","helpdesk","process","azure","soc","cdc","software","no","fi","se","dk","remote","other")]
      [string]$area = "cdc",

      [Parameter(
        Position = 6,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='How long a snooze is active in seconds')]
      [int]$snoozeTime = 14400
    )
    
    begin
    {
      <# Validate that Detector is not already created #>
      $scriptFile = $($name -replace ' ') + ".ps1"
      if (test-path $rootPath\detectors\$scriptFile)
      { 
        throw "$scriptFile already exists"
      }
      
      try {$doExist = Get-ODBCData -query "SELECT * FROM $inventoryTable WHERE detectorName LIKE '$name'" -EA stop}
      catch {throw $_}
      if ($doExist) {throw "Detector $name already exists in the database"}
    }
  
    process
    {
      <# Create new script file from template #>
      Get-Content -Path $rootPath\Tools\Detector\DetectorTemplate.ps1 | Set-Content -Path $rootPath\detectors\$scriptFile
      <# Create new detector in database #>
      Set-ODBCData -query "INSERT INTO $inventoryTable (detectorName, refreshRate, detectorEnvironment, heartBeatTimeOut, snoozeTime, area, isActive) VALUES ('$name', $refreshRate, '$detectorEnvironment', $heartBeatTimeOut, $snoozeTime, '$area', 'False')"
      <# Write event #>
      $currentSettings = Get-ODBCData -query "SELECT * FROM $inventoryTable WHERE (detectorName = '$name')"
      $detectorId = $currentSettings.detectorid
      $LocalEvent = @{
        detectorID = $detectorId;
        status = "green";
        eventShort = "Detector $name has been created but need to be activated.";
        contentType = "Text";
        descriptionDetails = "Detector $name has been created but need to be activated. The creation was made on $env:COMPUTERNAME by $env:USERNAME at $(get-date -Format 'yyyy-MM-dd HH:mm')"
      }
      Write-Event -LocalEvent $LocalEvent
    }
  }
  