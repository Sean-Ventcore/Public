This module is the evolution of an earlier prototype, and is more practically focused on
enabling easy creation of timelapses and associated helper functions (including capturing
images through cameras configured in an installation of the Agent DVR software, which was
more the focus of the previous prototype.)

The contents are as follows:

MODULE

TimelapseHelper.psm1 - the module itself
TimelapseHelper.format.ps1xml - module types file
TimelapseHelper.psd1 - module manifest file
TimelapseHelperConfig.psd1 - module config file

SCRIPTS (that use the module)

TakeSnapshots.ps1 - takes snapshots of the cameras named "1" and "2", to generate raw
data (i.e. when called via scheduled task every 5 minutes.)

TakeSolarNoonSnapshots.ps1 - uses the module to determine when solar noon is 
(based on longitude) and waits for that time, then takes snapshots of cameras "1" and "2".
Also intended to be called via scheduled task, probably around mid-morning so it's ahead 
of solar noon regardless of DST, etc. Using solar noon will hopefully reduce the choppy/jumpy
nature of shadows when using clock noon, mostly for timelapses with one frame per day, but 
it'll take some months (if not a year) of data to really see how much of a difference this makes.

Generate(Daily/Weekly/Monthly)Timelapse.ps1 - similar scripts which generate a timelapse
using ffmpeg (which must be installed separately, install path is set in
TimelapseHelperConfig.psd1) for the named time range, with some semi-reasonable values
set for frequency (i.e. a frame of video for every 5 minutes of real-time is good for 
a daily timelapse but would be too much for a monthly timelapse.)