$script:Token = $null
$script:Endpoint = "https://api.monday.com/v2"
$script:DefaultLimit = 10

#TODO: appropriate get/set/add/etc cmdlets for common object types
#TODO: support for pagination
#TODO: user-specified include/exclude fields in queries
#TODO: condense more of the query building into a single function
    #list of default fields, list and/or hashtable map for Kind or similar fields?
    #what about objects with sub-objects (User -> Account)

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
        
        if($responseType -eq "data" -or ($responseType -like "data" -eq "data"))
        {
            $data = $convertedContent.data
            $name = ($data | Get-Member -MemberType NoteProperty).Name
            
            $convertedContentWithTypedID = $responseContent.Replace("`"id`":",("`"{0}ID`":" -f $name)) | ConvertFrom-JSON
            $returnValue = $convertedContentWithTypedID.data.$name

            #final conversion for mutation/update queries
            if($returnValue.GetType().Name -eq "String")
            {
                $returnValue = $returnValue | ConvertFrom-JSON
            }

            return $returnValue
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
    [CmdletBinding(DefaultParameterSetName = 'NoFilter')]
    param
    (
        [Parameter(ParameterSetName='FilterByID')]
        [Parameter(ParameterSetName='FilterByOther')]
        [Parameter(ParameterSetName='NoFilter')]
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

function Get-MondayWorkspace
{
    [CmdletBinding(DefaultParameterSetName = 'NoFilter')]
    param
    (
        [Parameter(ParameterSetName='FilterByID')]
        [Parameter(ParameterSetName='FilterByOther')]
        [Parameter(ParameterSetName='NoFilter')]
        [Parameter(Mandatory=$false)][String]$Limit,
        
        [Parameter(ParameterSetName='FilterByID')][String]$ID,
        
        [Parameter(ParameterSetName='FilterByOther',Mandatory=$false)]
        [ValidateSet("Open","Closed")]
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

        $query = "query { workspaces$itemFilter {id name kind state} }"
        $result = ExecuteQuery -query $query
        $result
    }

    end
    {

    }
}

function Get-MondayUser
{
    [CmdletBinding(DefaultParameterSetName = 'NoFilter')]
    param
    (
        [Parameter(ParameterSetName='FilterByEmail')]
        [Parameter(ParameterSetName='FilterByOther')]
        [Parameter(ParameterSetName='NoFilter')]
        [Parameter(Mandatory=$false)][String]$Limit,
        
        [Parameter(ParameterSetName='FilterByEmail')][String]$Email,

        [Parameter(ParameterSetName='FilterByOther')][String]$Name,
        
        [Parameter(ParameterSetName='FilterByOther',Mandatory=$false)]
        [ValidateSet("All","NotGuest","Guest","NotPending")]
        [String]$Kind
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

        #Kind
        if($null -ne $Kind -and $Kind.Length -gt 0)
        {
            $map = @{"All"="all"; "NotGuest"="non_guests"; "Guest"="guests"; "NotPending"="non_pending"}
            $mapKind = $map[$Kind]
            $itemFilter = $itemFilter + "kind:$mapKind "
        }

        #Name
        if($null -ne $Name -and $Name.Length -gt 0)
        {
            $itemFilter = $itemFilter + "name:`"$Name`" ".ToLower()
        }

        #Email
        if($null -ne $Email -and $Email.Length -gt 0)
        {
            $itemFilter = $itemFilter + "emails:$Email "
        }

        #Finalize Filter
        if($null -ne $itemFilter)
        {
            $itemFilter = (" ({0})" -f $itemFilter.TrimEnd(' '))
        }

        $query = "query { users$itemFilter {email account { name id } } }"
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
        [Parameter(ParameterSetName='pipelineID',ValueFromPipelineByPropertyName,Mandatory=$true)]
        [String[]]$boardsID,

        [Parameter(ParameterSetName='FilterByID')]
        [String]$ID,

        [Parameter(ParameterSetName='FilterByID')]
        [Parameter(ParameterSetName='pipelineID')]
        [Parameter(Mandatory=$false)][String]$Name,

        [Parameter(ParameterSetName='FilterByID')]
        [Parameter(ParameterSetName='pipelineID')]
        [Parameter(Mandatory=$false)][String]$Description
    )

    begin
    {

    }

    process
    {
        if($null -ne $Name -and $Name.Length -gt 0)
        {
            $id = $_.boardsID
            $query = "mutation { update_board(board_id: $id, board_attribute: name, new_value: `"$Name`") }"
            $result = ExecuteQuery -query $query

            if($result.success -ne $true)
            {
                $name = $_.name
                Write-Warning "Error updating Board ID: $id Original Name: $name"
            }
        }

        if($null -ne $Description -and $Description.Length -gt 0)
        {
            $id = $_.boardsID
            $query = "mutation { update_board(board_id: $id, board_attribute: description, new_value: `"$Description`") }"
            $result = ExecuteQuery -query $query

            if($result.success -ne $true)
            {
                $name = $_.name
                Write-Warning "Error updating Board ID: $id Original Name: $name"
            }
        }
    }

    end
    {

    }
}

#endregion

#region not yet implemented cmdlets

function Add-MondayUserPermissions
{
    throw "Not yet implemented!"
    #TODO: accept user, board, or workspace from pipeline, require user or board/workspace as non-pipeline parameter
}

#endregion