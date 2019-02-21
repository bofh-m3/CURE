function Get-ODBCData {
  [CmdletBinding()]
  param
  (
    [Parameter(
      Position = 1,
      Mandatory = $True,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='SQL query')]
    [string]$query,

    [Parameter(
      Position = 2,
      Mandatory = $False,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='SQL server name')]
    [string]$server = $dbServer,

    [Parameter(
      Position = 3,
      Mandatory = $False,
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False,
      HelpMessage='Database Name')]
    [string]$database = $dbName,

    [Parameter(
        Position = 4,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='user Name')]
      [string]$userName = $dbUsername,

    [Parameter(
        Position = 5,
        Mandatory = $False,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $False,
        HelpMessage='Password')]
      [string]$pswd
  )
  
  begin
  {
    if (!($pswd))
    {
      try {$pswd = Receive-Credential -SavedCredential $userName -Type ClearText -EA stop}
      catch {throw $_}
    }
  }

  process
  {
    $conn = New-Object System.Data.Odbc.OdbcConnection
    $conn.ConnectionString = "Driver={PostgreSQL Unicode(x64)};Server=$server;Port=5432;Database=$database;Uid=$userName;Pwd=$pswd;"
    $conn.open()
    $cmd = New-object System.Data.Odbc.OdbcCommand($query,$conn)
    $ds = New-Object system.Data.DataSet
    (New-Object system.Data.odbc.odbcDataAdapter($cmd)).fill($ds) | out-null
    $conn.close()
    $ds.Tables[0]
  }
}
