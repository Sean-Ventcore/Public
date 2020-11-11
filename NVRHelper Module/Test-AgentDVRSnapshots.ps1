#Demo/test script for NVRHelper module - connects to specified Agent DVR server and
#takes a snapshot for each camera

Import-Module ".\NVRHelper.psd1"
Connect-NVRAgentDVR -server "localhost:8090"

Get-NVRCamera | New-NVRSnapshot