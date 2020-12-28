Connect-NVRAgentDVR -server 127.0.0.1:8090"

$targetTime = (Get-SolarNoon -Date (Get-Date) -Longitude -55.55555)

Start-Sleep -Milliseconds (($targetTime - (Get-Date)).TotalMilliseconds - 5)

Get-NVRCamera 1 | New-NVRSnapshot -Pattern "Solar{0}-{1}.jpg"
Get-NVRCamera 2 | New-NVRSnapshot -Pattern "Solar{0}-{1}.jpg"