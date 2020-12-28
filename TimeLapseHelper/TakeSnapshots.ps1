Connect-NVRAgentDVR -server "127.0.0.1:8090"
Get-NVRCamera 1 | New-NVRSnapshot -Pattern "{0}-{1}.jpg"
Get-NVRCamera 2 | New-NVRSnapshot -Pattern "{0}-{1}.jpg"