function Write-Log {
  [CmdletBinding()]
  param
  (
    [Parameter(
      Position = 1,
      Mandatory = $True,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='name of Detector script')]
    [string]$scriptName,

    [Parameter(
      Position = 2,
      Mandatory = $True,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='Error massage')]
    [string]$errorMessage,

    [Parameter(
      Position = 3,
      Mandatory = $False,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='Terminate after log has been written')]
    [switch]$exit
  )
  
  begin
  {
    $currentDate = (get-date -format yyyy-MM-dd)
    if (!(test-path $rootPath\log\$currentDate.error.log))
    {
      new-item $rootPath\log\$currentDate.error.log -itemtype file | out-null
    }
  }

  process
  {
    Add-Content -value "$(get-date); $scriptName; $errorMessage" -Path $rootPath\log\$currentDate.error.log -Force
    if ($exit)
    {
      Write-Warning "$scriptName - $errorMessage"
      Write-Warning "Exit in 5 seconds"
      Start-Sleep -Seconds 5
      Exit
    }
  }
}
