$script:Config = Import-PowerShellDataFile ($PSScriptRoot + "/M365HelperConfig.psd1")

function VerifyAuth
{
    if($null -eq $script:Config["appID"] -or $null -eq  $script:Config["thumbprint"])
    {
        throw "Provision and set appID and thumbprint values in script, config file, or import from desired credential store before using."
    }
}

function Get-PnPOneDrives
{
    #Will be replaced in later versions with a Get-PnPSites type cmdlet with switches to 
    #include/exclude various site types by template, etc
    [CmdletBinding()]
    param
    (
    )

    Connect-PnPOnline -Url ("https://{0}-admin.sharepoint.com" -f $script:Config["tenantName"]) -ClientID $script:Config["appID"] -Thumbprint $script:Config["thumbprint"] -Tenant $script:Config["tenantDomain"]
    $list = "DO_NOT_DELETE_SPLIST_TENANTADMIN_ALL_SITES_AGGREGATED_SITECOLLECTIONS"
    $manyDrives = Get-PnPListItem -List $list -Fields TemplateName,SiteUrl | where {$_.FieldValues["TemplateName"] -eq "SPSPERS#10"}

    return $manyDrives
}

function Get-SPOExtensionTypes
{
    [CmdletBinding()]
    param
    (
    )

    return $script:Config["extensionTypes"]
}

function Measure-SPOSiteFiles
{
    #Accepts site(s) via pipeline from either the tenant admin site list (PnP) or Get-SPOSite
    #and generates an analysis of file distribution by size/count based on the categories
    #defined in M365HelperConfig.psd1
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName="byPipeline",Mandatory=$true,ValueFromPipeline)]
        [object[]] $sites,
        [Parameter(ParameterSetName="byUrl",Mandatory=$true)]
        [String] $url
    )

    begin
    {
        #!! Verify PnP vs. SPO
        VerifyAuth
        $allSiteData = @{}
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq "byUrl")
        {
            $siteData = MeasureSingleSPOSiteFiles -url $url
            $allSiteData.Add($url, $siteData)
        }

        if($PSCmdlet.ParameterSetName -eq "byPipeline")
        {
            $url = $null
            if($null -ne $_.FieldValues -and $_.FieldValues.Keys -contains "SiteUrl")
            {
                $url = $_.FieldValues["SiteUrl"]
            }
            elseif($false)
            {
                #!! Implement property check/value extraction
            }
            else
            {
                Write-Warning "Site object not recognized, skipping!"    
            }

            if($null -ne $url)
            {
                $siteData = MeasureSingleSPOSiteFiles -url $url
                $allSiteData.Add($url, $siteData)
            }
        }
    }

    end
    {
        return $allSiteData
    }
}

function MeasureSingleSPOSiteFiles
{
    param
    (
        [Parameter(Mandatory=$true)]
        [String] $url
    )

    $url = $url.Trim("/") #drop trailing slashes for consistency - PnP cmdlets return URL without the trailing slash

    $siteData = @{}
    $extensionTypes = $script:Config["extensionTypes"]

    foreach($extensionType in $extensionTypes.Keys)
    {
        $siteData.Add(($extensionType+"_Count"),0)
        $siteData.Add(($extensionType+"_Size"),0)
    }

    $siteData.Add("TotalCount",0)
    $siteData.Add("TotalSize",[long]0)

    Connect-PnPOnline -Url $url -ClientID $script:Config["appID"] -Thumbprint $script:Config["thumbprint"] -Tenant $script:Config["tenantDomain"]
    
    #check url is really connected to avoid non-blocking PnP errors/failures
    $site = Get-PnPSite
    if($url -ne $site.Url)
    {
        Write-Warning ("Failed to connect to " + $site.Url)
    }
    else
    {
        #In almost all cases there will just be one Documents library, but this should catch any that were created by the user as well
        $libraries = Get-PnPList -Includes "IsSystemList" | where BaseType -eq "DocumentLibrary" | where IsSystemList -eq $false
        
        $libraryCount = 1
        foreach($docLib in $libraries)
        {
            Write-Progress -Id 1 -Activity ("Library #{0} out of {1}" -f $libraryCount, $libraries.Count) -PercentComplete (100*($libraryCount / $libraries.Count))
            Write-Progress -Id 2 -Activity ("Fetching files, please wait..." -f 0, $docLib.ItemCount) -PercentComplete 0 #there's a long pause for Get-PnPListItem so an early progress bar helps
            $allFiles = Get-PnPListItem -List $docLib.Id -PageSize 1000 
            
            $fileCount = 1
            foreach($file in $allFiles)
            {
                Write-Progress -ID 2 -Activity ("File #{0} out of {1}" -f $fileCount, $docLib.ItemCount) -PercentComplete (100*($fileCount / $docLib.ItemCount))
                $size = $file.FieldValues.SMTotalFileStreamSize
                $extension = $file.fieldValues.File_x0020_Type

                if($null -ne $extension)
                {
                    $found = $false
                    foreach($extensionType in $extensionTypes.Keys)
                    {
                        if($extensionTypes[$extensionType] -contains $extension.ToLower())
                        {
                            $siteData[("TotalCount")] += 1
                            $siteData[("TotalSize")] += $size

                            $found = $true
                            $siteData[($extensionType+"_Count")] += 1
                            $siteData[($extensionType+"_Size")] += $size
                        }
                    }

                    if(-not $found)
                    {
                        Write-Warning ("Extension not found! " + $extension)
                    }
                }
                $fileCount = $fileCount + 1
            }

            $libraryCount = $libraryCount + 1
        }

        return $siteData
    }
}