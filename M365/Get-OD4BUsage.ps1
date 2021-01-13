###
#   Get-OD4BUsage: second draft of a script to analyze breakdown 
#   of file type vs. size/count in all user OneDrives in an O365 tenant
#   as with any script querying user data, use with clear & direct approval 
#   and be mindful of ethical and legal considerations!
#   Could be easily adapted for SPO sites instead.
#   Changes:
#           1/13/2021:
#           -Converted basic report functionality to module with pipeline support
#           -Implemented PnP module or single URL support, SPO module support pending
#           12/29/2020:
#           -Converted to use PnP module to query sites, so that the SPO tenant module doesn't need to be used (simplifies authentication)
#           -Tested with the new PnP module and PowerShell 7 only
#   Likely improvements: 
#           -test performance against larger tenant and improve from there
#           -support for credentials vault/secure storage
#           -option to write to SPO site
###

###
#   Variables / Configuration / Init
###

Import-Module ".\M365Helper.psd1"

$divisor = "1MB" #file size will be divided by this

$path = "$HOME\Desktop\OD4B Reports\"
$filename = "OD4B Report {0} {1}.csv" #{0} for date, {1} for time
$fullPath = $path + ($filename -f (Get-Date).ToShortDateString().Replace("/","-"), (Get-Date).ToShortTimeString().Replace(":","."))

$reportData = Get-PnPOneDrives | Measure-SPOSiteFiles

$csvHeader = "Url,TotalCount,TotalSize"

$extensionTypes = Get-SPOExtensionTypes

foreach($extensionType in $extensionTypes.Keys)
{
    $csvHeader = $csvHeader + (",{0},{1}" -f ($extensionType+"_Count"), ($extensionType+"_Size ($divisor)"))
}

Add-Content -Path $fullPath $csvHeader

foreach($site in $reportData.Keys)
{
    $csvLine = ("{0},{1},{2}" -f $site, $reportData[$site]["TotalCount"], $reportData[$site]["TotalSize"].ToString("#.##"))

    foreach($extensionType in $extensionTypes.Keys)
    {
        $countKey = $extensionType+"_Count"
        $sizeKey = $extensionType+"_Size"

        $csvLine = $csvLine + (",{0},{1}" -f $reportData[$site][$countKey], ($reportData[$site][$sizeKey]/$divisor))
    }

    Add-Content -Path $fullPath $csvLine
}