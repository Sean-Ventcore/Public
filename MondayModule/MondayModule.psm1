$script:Token = $null
$script:Endpoint = "https://api.monday.com/v2"
$script:DefaultLimit = 10

#region Internal Functions
function ExecuteQuery
{
    param
    (
        [Parameter(Mandatory=$true)][String]$query,
        [Parameter(Mandatory=$false)][String]$vars
    )

    if($null -eq $script:Token)
    {
        Write-Warning "Use Connect-MondayService to authenticate before other cmdlets!"
    }
    else
    {
        $headers = @{"Authorization"=$script:Token; "Content-Type"="application/json"}
        $json = $null
        if($null -ne $vars -and $vars.Length -gt 0)
        {
            $json = @{"query"=$query; "variables"=$vars} | ConvertTo-Json
        }
        else
        {
            $json = @{"query"=$query} | ConvertTo-Json
        }
    }

    Write-Debug "JSON in ExecuteQuery: $json"

    $jsonResponse = Invoke-WebRequest -Uri $script:Endpoint -Method POST -Headers $headers -Body $json

    if($jsonResponse.StatusCode -eq "200")
    {
        $responseContent = $jsonResponse.Content
        $convertedContent = $responseContent | ConvertFrom-Json
        $responseType = ($convertedContent | Get-Member -MemberType NoteProperty).Name
        
        if($responseType -eq "data")
        {
            $data = $convertedContent.data
            $name = ($data | Get-Member -MemberType NoteProperty).Name
            
            $convertedContentWithTypedID = $responseContent.Replace("`"id`":",("`"{0}ID`":" -f $name)) | ConvertFrom-JSON
            
            return $convertedContentWithTypedID.data.$name
        }
        elseif($responseType -eq "errors") #errors from the Monday API side
        {
            Write-Error ("API response: {0}" -f $convertedContent.errors.message)
        }
        else
        {
            Write-Error "Unhandled response type $responseType"
        }
    }
    else
    {
        Write-Warning ("Response from server: {0}" -f $jsonResponse.StatusCode)
    }
}
#endregion

#region Connect/Misc cmdlets
function Connect-MondayService
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)][String]$Token
    )

    $script:Token = $Token
}
#endregion

#region Get Cmdlets
function Get-MondayBoard
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$false)][String]$Limit,
        
        [Parameter(ParameterSetName='FilterByID')][String]$ID,
        
        [Parameter(ParameterSetName='FilterByOther',Mandatory=$false)]
        [ValidateSet("Created","Used")]
        [String]$SortOrder,
        
        [Parameter(ParameterSetName='FilterByOther',Mandatory=$false)]
        [ValidateSet("Public","Private","Share")]
        [String]$Kind,

        [Parameter(ParameterSetName='FilterByOther',Mandatory=$false)]
        [ValidateSet("All","Active","Archived","Deleted")]
        [String]$State
    )

    begin
    {

    }

    process
    {
        #Result Limit
        $itemFilter = "limit:$script:DefaultLimit "
        if($null -ne $Limit -and $Limit.Length -gt 0)
        {
            if($Limit -eq "All")
            {
                $itemFilter = $null
            }
            elseif($null -ne ($Limit -as [int]))
            {
                $intLimit = $Limit -as [int]
                if($intLimit -eq 0) {$intLimit = $script:DefaultLimit}
                $itemFilter = "limit:$Limit "
            }
        }

        #Sort Order
        if($null -ne $SortOrder -and $SortOrder.Length -gt 0)
        {
            $itemFilter = $itemFilter + ("order_by:{0}_at " -f $SortOrder).ToLower()
        }

        #Kind
        if($null -ne $Kind -and $Kind.Length -gt 0)
        {
            $itemFilter = $itemFilter + "board_kind:$Kind ".ToLower()
        }

        #State
        if($null -ne $State -and $State.Length -gt 0)
        {
            $itemFilter = $itemFilter + "state:$State ".ToLower()
        }

        #ID
        if($null -ne $ID -and $ID.Length -gt 0)
        {
            $itemFilter = $itemFilter + "ids:$ID "
        }

        #Finalize Filter
        if($null -ne $itemFilter)
        {
            $itemFilter = (" ({0})" -f $itemFilter.TrimEnd(' '))
        }

        $query = "query { boards$itemFilter {id name board_kind state type} }"
        $result = ExecuteQuery -query $query
        $result
    }

    end
    {

    }
}
#endregion

#region Set Cmdlets

function Set-MondayBoard
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName='pipelineID',ValueFromPipelineByPropertyName,Mandatory=$true)][String[]]$boardsID
    )

    begin
    {

    }

    process
    {
        Write-Host $_.name
    }

    end
    {

    }
}

#endregion