###
#   Get-OD4BUsage: second draft of a script to analyze breakdown 
#   of file type vs. size/count in all user OneDrives in an O365 tenant
#   as with any script querying user data, use with clear & direct approval 
#   and be mindful of ethical and legal considerations!
#   Could be easily adapted for SPO sites instead.
#   Changes:
#           12/29/2020:
#           -Converted to use PnP module to query sites, so that the SPO tenant module doesn't need to be used (simplifies authentication)
#           -Tested with the new PnP module and PowerShell 7 only
#   Likely improvements: 
#           -convert to a module to separate processing of individual sites (in module) from selection of sites (in script)
#           -move file type configuration to external source
#           -test performance against larger tenant and improve from there
#           -switch to Azure AD app authentication
#           -support for credentials vault/secure storage
#           -option to write to SPO site
#           -run for individual user
###

###
#   Variables / Configuration
###

$tenantName = "ventcore"
$tenantDomain = "ventcore.org"
$divisor = "1MB" #file size will be divided by this

$path = "$HOME\Desktop\OD4B Reports\"
$filename = "OD4B Report {0} {1}.csv" #{0} for date, {1} for time
$fullPath = $path + ($filename -f (Get-Date).ToShortDateString().Replace("/","-"), (Get-Date).ToShortTimeString().Replace(":","."))

$extensionTypes = @{}

$extensionTypes.Add("Text",@("doc","docx","txt"))
$extensionTypes.Add("Images",@("cr2","jpg"))
$extensionTypes.Add("Spreadsheets",@("xls","xlsx","ods"))
$extensionTypes.Add("PDF",@("pdf"))
$extensionTypes.Add("Scripts",@("ps1","psm1","bat","py"))
$extensionTypes.Add("Code",@("cs","resx","settings","csproj","pdb","cache","sln","manifest","resources","suo"))
$extensionTypes.Add("Music",@("mp3","ogg"))
$extensionTypes.Add("Video",@("mp4","mov","avi","mpg","mpeg","mkv"))
$extensionTypes.Add("Data",@("xml"))
$extensionTypes.Add("Archives",@("zip","rar"))
$extensionTypes.Add("Passwords",@("kdbx"))
$extensionTypes.Add("Executables",@("exe"))
$extensionTypes.Add("Other",@("thm"))

###
#   Check for connection/connect to SPO and input PnP credentials
#   AppID/thumbprint created as per 
#   https://docs.microsoft.com/en-us/powershell/module/sharepoint-pnp/initialize-pnppowershellauthentication?view=sharepoint-ps
#   With default permissions, but those could/should be downgraded to read-only unless needed for other scripts
###

$appID = $null
$thumbprint = $null

if($null -eq $appID -or $null -eq $thumbprint)
{
    throw "Provision and set appID and thumbprint values in script, config file, or import from desired credential store before using."
}

###
#   Load users
###

$allUserData = @{}

#$manyDrives = Get-SPOSite -IncludePersonalSite $true -Template "SPSPERS#10" -Limit All

Connect-PnPOnline -Url https://$tenantName-admin.sharepoint.com -ClientID $appID -Thumbprint $thumbprint -Tenant $tenantDomain
$list = "DO_NOT_DELETE_SPLIST_TENANTADMIN_ALL_SITES_AGGREGATED_SITECOLLECTIONS"
$manyDrives = Get-PnPListItem -List $list -Fields TemplateName,SiteUrl | where {$_.FieldValues["TemplateName"] -eq "SPSPERS#10"}

$userCount = 1

foreach($oneDrive in $manyDrives)
{
    Write-Progress -Activity ("Analyzing OD4B #{0} of {1}" -f $userCount, $manyDrives.Count) -PercentComplete (100*($userCount / $manyDrives.Count))
    $userData = @{}

    foreach($extensionType in $extensionTypes.Keys)
    {
        $userData.Add(($extensionType+"_Count"),0)
        $userData.Add(($extensionType+"_Size"),0)
    }

    $userData.Add("TotalCount",0)
    $userData.Add("TotalSize",[long]0)

    Connect-PnPOnline -Url $oneDrive.FieldValues["SiteUrl"] -ClientID $appID -Thumbprint $thumbprint -Tenant $tenantDomain
    
    #check url is really connected to avoid non-blocking PnP errors/failures
    $site = Get-PnPSite
    if($oneDrive.FieldValues["SiteUrl"] -ne $site.Url)
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
                            $userData[("TotalCount")] += 1
                            $userData[("TotalSize")] += $size

                            $found = $true
                            $userData[($extensionType+"_Count")] += 1
                            $userData[($extensionType+"_Size")] += $size
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

        $allUserData.Add($oneDrive.FieldValues["SiteUrl"], $userData)
    }

    $userCount = $userCount + 1
}

$csvHeader = "TotalCount,TotalSize"

foreach($extensionType in $extensionTypes.Keys)
{
    $csvHeader = $csvHeader + (",{0},{1}" -f ($extensionType+"_Count"), ($extensionType+"_Size ($divisor)"))
}

Add-Content -Path $fullPath $csvHeader

foreach($user in $allUserData.Keys)
{
    $csvLine = ("{0},{1}" -f $userData["TotalCount"], $userData["TotalSize"].ToString("#.##"))

    foreach($extensionType in $extensionTypes.Keys)
    {
        $countKey = $extensionType+"_Count"
        $sizeKey = $extensionType+"_Size"

        $csvLine = $csvLine + (",{0},{1}" -f $allUserData[$user][$countKey], ($allUserData[$user][$sizeKey]/$divisor))
    }

    Add-Content -Path $fullPath $csvLine
}