$date = Get-Date
$start = $date.AddDays(-7)
$end = $date
$name = "Weekly-{0}-" + $date.ToString("yyyyMMdd")
$cameras = @("1","2")
$freq = New-TimeSpan -Minutes 60
$capRate = New-TimeSpan -Minutes 5

foreach($camera in $cameras)
{
    New-Timelapse -Camera $camera -Name ($name -f $camera) -Start $start -End $end -Frequency $freq -Framerate 30 -CaptureRate $capRate -MissingFrames Duplicate
}