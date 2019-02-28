function Get-Workhours {
  [CmdletBinding()]
  param
  (
    [Parameter(
      Position = 1,
      Mandatory = $true,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='Date object')]
    [datetime]$StartDate,

    [Parameter(
      Position = 2,
      Mandatory = $false,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='Date object')]
    [int]$WorkStartHour = 8,

    [Parameter(
      Position = 3,
      Mandatory = $false,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='Date object')]
    [int]$WorkEndHour = 18
  )

  $CurrentDate = (get-date)
  $WorkHours = $WorkStartHour..$WorkEndHour
  $Hours = 0

  if ($StartDate -gt $CurrentDate) {throw "StartDate is in the future"}

  if ($StartDate.ToShortDateString() -like $CurrentDate.ToShortDateString())
  { <##START SAME DAY AS CURRENT##>
    if (Test-Holiday $StartDate) {Return $Hours}
    elseif ([int]$CurrentDate.Hour -le $WorkStartHour) {Return $Hours}
    elseif ([int]$StartDate.Hour -ge $WorkEndHour) {Return $Hours}
    else
    {
      if ([int]$StartDate.Hour -in $WorkHours)
      { <##START WITHIN WORKING HOURS##>
        if ([int]$CurrentDate.Hour -gt $WorkEndHour) {$Hours += ($WorkEndHour - [int]$StartDate.Hour)}
        else {$Hours += ([int]$CurrentDate.Hour - [int]$StartDate.Hour)}
      }
      else
      {<##START BEFORE WORKING HOURS##>
        if ([int]$CurrentDate.Hour -gt $WorkEndHour) {$Hours += ($WorkEndHour - $WorkStartHour)}
        else {$Hours += ([int]$CurrentDate.Hour - $WorkStartHour)}
      }
    }
  }
  else
  {<##MULTIPLE DAYS##>
    $DateArray = @()
    for ($i = $StartDate; $i.ToShortDateString() -le $CurrentDate.ToShortDateString(); $i = $i.AddDays(1))
    {
      $DateArray += $i.ToShortDateString()
    }
    $WorkDates = $DateArray | where {(!(Test-Holiday $_))}

    foreach ($day in $WorkDates)
    {
      if ($CurrentDate.ToShortDateString() -like $day)
      { ### Last Day ###
        if ([int]$CurrentDate.Hour -le $WorkStartHour) {Continue}
        elseif ([int]$CurrentDate.Hour -ge $WorkEndHour) {$Hours += ($WorkEndHour - $WorkStartHour)}
        else {$Hours += ([int]$CurrentDate.Hour - $WorkStartHour)}
      }
      elseif ($StartDate.ToShortDateString() -like $day)
      { ## First Day ##
        if ([int]$StartDate.Hour -ge $WorkEndHour) {Continue}
        elseif ([int]$StartDate.Hour -lt $WorkStartHour) {$Hours += ($WorkEndHour - $WorkStartHour)}
        else {$Hours += ($WorkEndHour - [int]$StartDate.Hour)}
      }
      else
      { ## Inbetween Day(s) ##
        $Hours += ($WorkEndHour - $WorkStartHour)
      }
    }
  }
  Return $Hours
}
