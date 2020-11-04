###
#   Get-OD4BUsage: quick & dirty script to analyze breakdown 
#   of file type vs. size/count in all user OneDrives in an O365 tenant
#   as with any script querying user data, use with approval and be mindful
#   of ethical and legal considerations!
#   Could be easily adapted for SPO sites instead.
#   Likely improvements: 
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

$tenant = "ventcore"
$divisor = "1MB" #file size will be divided by this

$path = "$HOME\Desktop\OD4B Reports\"
$filename = "OD4B Report {0} {1}.csv" #{0} for date, {1} for time
$fullPath = $path + ($filename -f (Get-Date).ToShortDateString().Replace("/","-"), (Get-Date).ToShortTimeString().Replace(":","."))

$extensionTypes = @{}

$extensionTypes.Add("Word",@("doc","docx","txt"))
$extensionTypes.Add("Images",@("cr2","jpg"))
$extensionTypes.Add("Spreadsheets",@("xls","xlsx","ods"))
$extensionTypes.Add("PDF",@("pdf"))
$extensionTypes.Add("Scripts",@("ps1","psm1","bat","py"))
$extensionTypes.Add("Code",@("cs","resx","settings","csproj","pdb","cache","sln","manifest","resources","suo"))
$extensionTypes.Add("Music",@("mp3","ogg"))
$extensionTypes.Add("Video",@("mp4","mov","avi","mpg","mpeg"))
$extensionTypes.Add("Data",@("xml"))
$extensionTypes.Add("Archives",@("zip","rar"))
$extensionTypes.Add("Passwords",@("kdbx"))
$extensionTypes.Add("Executables",@("exe"))
$extensionTypes.Add("Other",@("thm"))

###
#   Check for connection/connect to SPO and input PnP credentials
#   AppID/Secret created as per 
#   https://docs.microsoft.com/en-us/sharepoint/dev/solution-guidance/security-apponly-azureacs
#   With read-only tenant-wide access
###

try
{
    Get-SPOTenant | Out-Null
}
catch
{
    Connect-SPOService -url https://$tenant-admin.sharepoint.com
}

$appID = Read-Host "Enter the AppID"
$appSecret = Read-Host "Enter the App Secret"

###
#   Load users
###

$allUserData = @{}

$manyDrives = Get-SPOSite -IncludePersonalSite $true -Template "SPSPERS#10" -Limit All
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

    Connect-PnPOnline -Url $oneDrive.Url -ClientID $appID -ClientSecret $appSecret
    
    #check url is really connected to avoid non-blocking PnP errors/failures
    $site = Get-PnPSite
    if($oneDrive.Url -ne $site.Url)
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

        $allUserData.Add($oneDrive.Owner, $userData)
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