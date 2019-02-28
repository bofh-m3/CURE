function Test-Holiday {
  [CmdletBinding()]
  param
  (
    [Parameter(
      Position = 1,
      Mandatory = $false,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='Date object')]
    [datetime]$date = (get-date),
	
	[Parameter(
      Position = 2,
      Mandatory = $false,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='Path to holiday csv folder')]
    [string]$csvpath = "$rootPath\other"
  )

  if (!(Test-Path $csvpath\holidays.$year.csv))
  {
    $holidays = Invoke-RestMethod -Method Get -Uri "https://api.dryg.net/dagar/v2.1/$year"
    try {($holidays.dagar | where {$_.'arbetsfri dag' -like "Ja"}).datum -join ',' | Out-File -FilePath $csvpath\holidays.$year.csv -Encoding utf8 -NoClobber -ErrorAction stop}
	catch {}
  }
  if (Test-Path E:\CURE\other\holidays.$($date.Year).csv)
  {
    $holidays = (Get-Content -Path E:\CURE\other\holidays.2019.csv).Split(',') | where {$_ -notlike "$($date.Year)-06-06"}
    if ($date.ToShortDateString() -in $holidays)
    {
      return $true
    }
    else
    {
      return $false
    }
  }
  else
  {
    if ($date.DayOfWeek -in @("Saturday","Sunday"))
    {
      return $true
    }
    else
    {
      return $false
    }
  }
}
