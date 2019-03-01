function Get-RedmineIssue {
  [CmdletBinding()]
  param
  (
    [Parameter(
      Position=1,
      Mandatory=$False,
      ValueFromPipeline=$True,
      ValueFromPipelineByPropertyName=$True,
      HelpMessage='Sepecific ID(s)')]
    [int[]]$ID,

    [Parameter(
      Position=2,
      Mandatory=$False,
      ValueFromPipeline=$True,
      ValueFromPipelineByPropertyName=$True,
      HelpMessage='Sepecific ID(s)')]
    [ValidateSet("children","attachments","relations","changesets","journals","watchers","All")]
    [string[]]$Include,

    [Parameter(
      Position=3,
      Mandatory=$False,
      ValueFromPipeline=$True,
      ValueFromPipelineByPropertyName=$True,
      HelpMessage='Open filter options')]
    [switch]$Filter,

    [Parameter(
      Position=10,
      Mandatory=$False,
      ValueFromPipeline=$False,
      ValueFromPipelineByPropertyName=$False,
      HelpMessage='Root uri to redmine')]
    [string]$Uri,

    [Parameter(
      Position=11,
      Mandatory=$False,
      ValueFromPipeline=$False,
      ValueFromPipelineByPropertyName=$False,
      HelpMessage='ApiKey of admin user')]
    [string]$ApiKey
  )

  DynamicParam
  {
    if ($Filter) 
    {

      $ParameterName1 = 'ProjectID'
      $ParameterName2 = 'IncludeSubProjects'
      $ParameterName3 = 'TrackerID'
      $ParameterName4 = 'Status'
      $ParameterName5 = 'AssignedToID'
      $ParameterName6 = 'AgeDays'

      $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
      $AttributeCollection1 = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
      $AttributeCollection2 = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
      $AttributeCollection3 = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
      $AttributeCollection4 = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
      $AttributeCollection5 = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
      $AttributeCollection6 = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
      $ParameterAttribute1 = New-Object System.Management.Automation.ParameterAttribute
      $ParameterAttribute2 = New-Object System.Management.Automation.ParameterAttribute
      $ParameterAttribute3 = New-Object System.Management.Automation.ParameterAttribute
      $ParameterAttribute4 = New-Object System.Management.Automation.ParameterAttribute
      $ParameterAttribute5 = New-Object System.Management.Automation.ParameterAttribute
      $ParameterAttribute6 = New-Object System.Management.Automation.ParameterAttribute
      $ParameterAttribute1.Mandatory = $False
      $ParameterAttribute1.Position = 4
      $AttributeCollection1.Add($ParameterAttribute1)
      $ParameterAttribute2.Mandatory = $False
      $ParameterAttribute2.Position = 5
      $AttributeCollection2.Add($ParameterAttribute2)
      $ParameterAttribute3.Mandatory = $False
      $ParameterAttribute3.Position = 6
      $AttributeCollection3.Add($ParameterAttribute3)
      $ParameterAttribute4.Mandatory = $False
      $ParameterAttribute4.Position = 7
      $AttributeCollection4.Add($ParameterAttribute4)
      $ParameterAttribute5.Mandatory = $False
      $ParameterAttribute5.Position = 8
      $AttributeCollection5.Add($ParameterAttribute5)
      $ParameterAttribute6.Mandatory = $False
      $ParameterAttribute6.Position = 9
      $AttributeCollection6.Add($ParameterAttribute6)

      #----  Generate and set the ValidateSet ----#
      $arrSet4=@("open","closed","All")
      #-------------------------------------------#
      $ValidateSetAttribute4 = New-Object System.Management.Automation.ValidateSetAttribute($arrSet4)
      $AttributeCollection4.Add($ValidateSetAttribute4)

      $RuntimeParameter1 = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName1, [int], $AttributeCollection1)
      $RuntimeParameter2 = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName2, [switch], $AttributeCollection2)
      $RuntimeParameter3 = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName3, [int], $AttributeCollection3)
      $RuntimeParameter4 = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName4, [string], $AttributeCollection4)
      $RuntimeParameter5 = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName5, [int], $AttributeCollection5)
      $RuntimeParameter6 = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName6, [int], $AttributeCollection6)
      $RuntimeParameterDictionary.Add($ParameterName1, $RuntimeParameter1)
      $RuntimeParameterDictionary.Add($ParameterName2, $RuntimeParameter2)
      $RuntimeParameterDictionary.Add($ParameterName3, $RuntimeParameter3)
      $RuntimeParameterDictionary.Add($ParameterName4, $RuntimeParameter4)
      $RuntimeParameterDictionary.Add($ParameterName5, $RuntimeParameter5)
      $RuntimeParameterDictionary.Add($ParameterName6, $RuntimeParameter6)
      return $RuntimeParameterDictionary
    }
  }

  begin
  {
    if (!$Uri)
    {
      if ([string]::IsNullOrEmpty($DefaultRedmineURI)) {throw "Provide redmine Uri"}
      else {$Uri=$DefaultRedmineURI}
    }
    if (!$ApiKey)
    {
      try {$ApiKey=Receive-Credential -Type ClearText -SavedCredential $DefaultRedmineApiKey -ea stop}
      catch {throw "Provide ApiKey or run `"Save-Credential $DefaultRedmineApiKey`" to set default"}
    }
  }

  process
  {
    $result=@()
    $baseurlname = $Uri + '/issues.json?key=' + $ApiKey + '&limit=100'
    $header=@{"Content-Type"="application/json"}
    if (($Filter) -and ($ID)) {throw "specify only ID or Filter"}
    elseif ($ID)
    {
      foreach ($i in $ID)
      {
        $curl=$Uri+'/issues/'+$i+'.json?key='+$ApiKey
        if ($Include)
        {
          if ($Include -like "All") {$curl=$curl+"&include=children,attachments,relations,changesets,journals,watchers"}
          else {$curl=$curl+"&include="+$($Include -join ',')}
        }
        $cfetch=Invoke-RestMethod $curl -Method get -headers $header
        $result+=$cfetch.issue
      }
    }
    elseif ($Filter)
    {
      $ProjectID=$PsBoundParameters[$ParameterName1]
      $IncludeSubProjects=$PsBoundParameters[$ParameterName2]
      $TrackerID=$PsBoundParameters[$ParameterName3]
      $Status=$PsBoundParameters[$ParameterName4]
      $AssignedToID=$PsBoundParameters[$ParameterName5]
      $AgeDays=$PsBoundParameters[$ParameterName6]
      $curl=$baseurlname
      if ($ProjectID) 
      {
         if ($IncludeSubProjects){$curl+="&project_id="+$ProjectID}
         else {$curl+="&project_id="+$ProjectID+'&subproject_id=!*'}
      }
      if ($TrackerID){$curl+="&tracker_id="+$TrackerID}
      if ($Status)
      {
        if ($Status -like "All") {$curl+="&status_id=*"}
        else {$curl+="&status_id="+$Status}
      }
      if ($AssignedToID){$curl+="&assigned_to_id="+$AssignedToID}
      if ($AgeDays)
      {
        $curl+="&sort=updated_on:desc"
        $AgeDate=(get-date).AddDays(-$AgeDays)
        $cfetch=Invoke-RestMethod $curl -Method get -headers $header
        $cfetchfiltered=$cfetch.issues | where {[datetime]$_.updated_on -ge $AgeDate}
        $result+=$cfetchfiltered
        if ($cfetchfiltered.count -ge 100)
        {
          $offset=100
          while ($cfetchfiltered.count -ge 100)
          {
            $dcurl=$curl+"&offset=$offset"
            $cfetch=Invoke-RestMethod $dcurl -Method get -headers $header
            $cfetchfiltered=$cfetch.issues | where {[datetime]$_.updated_on -ge $AgeDate}
            $result+=$cfetchfiltered
            $offset+=100
          }
        }
      }
      else
      {
        $cfetch=Invoke-RestMethod $curl -Method get -headers $header
        $result+=$cfetch.issues
        if ($cfetch.total_count -gt 100)
        {
          $offset=100
          $num=1
          $fetches=[math]::floor(($cfetch.total_count)/100)
          while ($num -le $fetches)
          {
            $dcurl=$curl+"&offset=$offset"
            $cfetch=Invoke-RestMethod $dcurl -Method get -headers $header
            $result+=$cfetch.issues
            $num+=1
            $offset+=100
          }
        }
      }
    }
    else
    {
      $curl=$baseurlname
      $cfetch=Invoke-RestMethod $curl -Method get -headers $header
      $result+=$cfetch.issues
      if ($cfetch.total_count -gt 100)
      {
        $offset=100
        $num=1
        $fetches=[math]::floor(($cfetch.total_count)/100)
        while ($num -le $fetches)
        {
          $dcurl=$curl+"&offset=$offset"
          $cfetch=Invoke-RestMethod $dcurl -Method get -headers $header
          $result+=$cfetch.issues
          $num+=1
          $offset+=100
        }
      }
    }
    return $result
  }
}
