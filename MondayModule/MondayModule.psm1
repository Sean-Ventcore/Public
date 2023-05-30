$script:Token = $null
$script:Config = Import-PowerShellDataFile ($PSScriptRoot + "/MondayModuleConfig.psd1")

#TODO: support for pagination
#TODO: user-specified include/exclude fields in queries
#TODO: better generic handling of multiple fields in Set-*

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
        $headers = @{"Authorization"=$script:Token; "Content-Type"=$script:Config["ContentType"]}
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

    $jsonResponse = Invoke-WebRequest -Uri $script:Config["Endpoint"] -Method POST -Headers $headers -Body $json

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

    process
    {
        #Result Limit
        $itemFilter = "limit:{0} " -f $script:Config["DefaultLimit"]
        if($null -ne $Limit -and $Limit.Length -gt 0)
        {
            if($Limit -eq "All")
            {
                $itemFilter = $null
            }
            elseif($null -ne ($Limit -as [int]))
            {
                $intLimit = $Limit -as [int]
                if($intLimit -eq 0) {$intLimit = $script:Config["DefaultLimit"]}
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
        
        return ExecuteQuery -query $query
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

    process
    {
        #Result Limit
        $itemFilter = "limit:{0} " -f $script:Config["DefaultLimit"]
        if($null -ne $Limit -and $Limit.Length -gt 0)
        {
            if($Limit -eq "All")
            {
                $itemFilter = $null
            }
            elseif($null -ne ($Limit -as [int]))
            {
                $intLimit = $Limit -as [int]
                if($intLimit -eq 0) {$intLimit = $script:Config["DefaultLimit"]}
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
        return ExecuteQuery -query $query
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

    process
    {
        #Result Limit
        $itemFilter = "limit:{0} " -f $script:Config["DefaultLimit"]
        if($null -ne $Limit -and $Limit.Length -gt 0)
        {
            if($Limit -eq "All")
            {
                $itemFilter = $null
            }
            elseif($null -ne ($Limit -as [int]))
            {
                $intLimit = $Limit -as [int]
                if($intLimit -eq 0) {$intLimit = $script:Config["DefaultLimit"]}
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

        return ExecuteQuery -query $query
    }

}

function Get-MondayPlan
{
    [CmdletBinding()] param()

    process
    {
        $query = "query { account { plan { max_users period tier version } } }"
        return ExecuteQuery -query $query
    }
}

function Get-MondayTeam
{
    [CmdletBinding(DefaultParameterSetName = 'NoFilter')]
    param
    (
        [Parameter(ParameterSetName='FilterByID')][String]$ID,
        [Parameter()][Switch]$IncludeUsers
    )

    process
    {
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
        if($IncludeUsers)
        {
            $query = "query$itemFilter { teams { id name users { email } } }"
        }
        else
        {
            $query = "query$itemFilter { teams { id name } }"
        }
        
        return ExecuteQuery -query $query
    }
}

function Get-MondayActivityLog
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName='PipelineID',ValueFromPipelineByPropertyName,Mandatory=$true)]
        [String[]]$boardsID,

        [Parameter(ParameterSetName='SingleID',Mandatory=$true)]
        [String]$BoardID,

        [Parameter(ParameterSetName='SingleID',Mandatory=$true)]
        [Parameter(ParameterSetName='PipelineID',Mandatory=$true)]
        [DateTime]$Start,

        [Parameter(ParameterSetName='SingleID',Mandatory=$true)]
        [Parameter(ParameterSetName='PipelineID',Mandatory=$true)]
        [DateTime]$End
    )

    process
    {
        $utcISO8601Start = $Start.ToUniversalTime() | get-date -Format o
        $utcISO8601End = $End.ToUniversalTime() | get-date -Format o

        $id = $null
        if($PSCmdlet.ParameterSetName -eq "PipelineID")
        {
            $id = $_.boardsID
        }

        if($PSCmdlet.ParameterSetName -eq "SingleID")
        {
            $id = $BoardID
        }

        $query = "query { boards (ids: $id) { activity_logs (from: `"$utcISO8601Start`", to: `"$utcISO8601End`") { id event data } } }"
        
        return ExecuteQuery -query $query
    }
}

#endregion

#region Add&Set Cmdlets

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
}

#endregion

#region not yet implemented cmdlets

function Add-MondayFile
{
    throw "Not yet implemented!"
    #TODO: accept file in pipeline? or just via path? then upload file to alternate endpoint
}

#Adding team/user permissions to boards/workspaces - simplify for now by breaking up into cmdlet for each combo? taking objects vs. IDs? only take objects via pipeline?

#Skipping for now due to lesser relevance: 
    #app subscription/monetization status, board views, folders, me, notifications(create only)
    #tags, updates

#Skipping for now due to complexity of implementation: 
    #columns/column values, docs/blocks, groups, items, subitems,

#endregion