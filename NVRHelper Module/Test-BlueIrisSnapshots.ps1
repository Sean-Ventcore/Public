#Demo/test script for NVRHelper module - connects to specified BlueIris server and
#takes a snapshot for each camera - uses CredentialManager module to store/retrieve API user
#details via the Windows Credential Manager

Import-Module ".\NVRHelper.psd1"
Connect-NVRBlueIris -server "127.0.0.1:81" -credential (Get-StoredCredential -target "BlueIris")

Get-NVRCamera | New-NVRSnapshot