###
#   Get-OD4BUsage: quick & dirty script to analyze breakdown 
#   of file type vs. size/count in all user OneDrives in an O365 tenant
#   as with any script querying user data, use with approval and be mindful
#   of ethical and legal considerations!
#   Could be easily adapted for SPO sites instead.
#   Likely improvements: 
#           -move file type configuration to external source, 
#           -test performance against larger tenant and improve from there
#           -switch to Azure AD app authentication
#           -support for credentials vault/secure storage
#           -write to CSV for further processing/graphing
#           -progress bars
#           -calculate percentage of total count/size per type
###

###
#   Variables
###

$tenant = "ventcore"
$divisor = "1MB" #file size will be divided by this

$extensionTypes = @{}

$extensionTypes.Add("Word",@("doc","docx"))
$extensionTypes.Add("Images",@("cr2","jpg"))
$extensionTypes.Add("Excel",@("xls","xlsx"))
$extensionTypes.Add("PDF",@("pdf"))
$extensionTypes.Add("Scripts",@("ps1","psm1","bat","py"))
$extensionTypes.Add("Code",@("cs","resx","settings","csproj","pdb","cache","sln","manifest","resources"))
$extensionTypes.Add("Music",@("mp3","ogg"))
$extensionTypes.Add("Video",@("mp4","mov","avi","mpg","mpeg"))
$extensionTypes.Add("Data",@("xml"))
$extensionTypes.Add("Text",@("txt"))
$extensionTypes.Add("Archives",@("zip","rar"))
$extensionTypes.Add("Passwords",@("kdbx"))
$extensionTypes.Add("Executables",@("exe"))

###
#   Connect to O365 and input PnP credentials
#   AppID/Secret created as per 
#   https://docs.microsoft.com/en-us/sharepoint/dev/solution-guidance/security-apponly-azureacs
#   With read-only tenant-wide access
###

Connect-SPOService -url https://$tenant-admin.sharepoint.com
$appID = Read-Host "Enter the AppID"
$appSecret = Read-Host "Enter the App Secret"

###
#   Load users
###

$allUserData = @{}

$manyDrives = Get-SPOSite -IncludePersonalSite $true -Template "SPSPERS#10" -Limit All

foreach($oneDrive in $manyDrives)
{
    $userData = @{}
    Connect-PnPOnline -Url $oneDrive.Url -ClientID $appID -ClientSecret $appSecret
    
    #check url is really connected

    #In almost all cases there will just be one Documents library, but this should catch any that were created by the user as well
    $libraries = Get-PnPList -Includes "IsSystemList" | where BaseType -eq "DocumentLibrary" | where IsSystemList -eq $false
    
    foreach($docLib in $libraries)
    {
        $allFiles = Get-PnPListItem -List $docLib.Id -PageSize 1000 
        foreach($file in $allFiles)
        {
            $size = $file.FieldValues.SMTotalFileStreamSize / $divisor
            $extension = $file.fieldValues.File_x0020_Type

            if($null -ne $extension)
            {
                $found = $false
                foreach($extensionType in $extensionTypes.Keys)
                {
                    if($extensionTypes[$extensionType] -contains $extension.ToLower())
                    {
                        $found = $true
                        if($userData.Keys -notcontains ($extensionType+"_Count"))
                        {
                            #First case of this extension type for this user, start count
                            $userData.Add(($extensionType+"_Count"),1)
                        }
                        else 
                        {
                            #Subsequent cases, add to count
                            $userData[($extensionType+"_Count")] += 1
                        }

                        if($userData.Keys -notcontains ($extensionType+"_Size"))
                        {
                            #First case of this extension type for this user, start count
                            $userData.Add(($extensionType+"_Size"),$size)
                        }
                        else 
                        {
                            #Subsequent cases, add to count
                            $userData[($extensionType+"_Size")] += $size
                        }
                    }
                }

                if(-not $found)
                {
                    Write-Warning ("Extension not found! " + $extension)
                }
            }
        }
    }

    $allUserData.Add($oneDrive.Owner, $userData)
}

Write-Host "---------------------"
foreach($user in $allUserData.Keys)
{
    Write-Host "Report for $user"

    foreach($extensionType in $extensionTypes.Keys)
    {
        $countKey = $extensionType+"_Count"
        $sizeKey = $extensionType+"_Size"

        if($allUserData[$user].Keys -contains $countKey)
        {
            Write-Host "$extensionType count: " $allUserData[$user][$countKey]
        }

        if($allUserData[$user].Keys -contains $sizeKey)
        {
            Write-Host "$extensionType size ($divisor): " $allUserData[$user][$sizeKey]
        }
    }

    Write-Host "---------------------"
}