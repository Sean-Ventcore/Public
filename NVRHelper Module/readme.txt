This is an early, rough prototype of a module for interacting with NVR (network
video recorder) software. The immediate practical application for me is to give
greater control over taking snapshots to collate into timelapse footage. The
NVR software eliminates the need to interact with the cameras directly, store
configuration/authentication details, etc.

It also serves as a non-work-related testbed for module development, currently
focusing on the PowerShell type system as it relates to modules.

Current functionality includes connecting to a BlueIris or Agent DVR system on
the local host, retrieving a list of cameras or specific camera, and taking
snapshots from the video feed of those cameras. Documentation, error handling,
and other necessary detailed touches are currently lacking, to be expanded upon
as time allows and the structure of the module starts to solidify.

See the Test-*Snapshots.ps1 files for examples of implementation.