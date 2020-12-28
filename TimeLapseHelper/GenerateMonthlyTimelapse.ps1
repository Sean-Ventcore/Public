$date = Get-Date
$start = $date.AddMonths(-1)
$end = $date
$name = "Monthly-{0}-" + $date.ToString("yyyyMMdd")
$cameras = @("1","2")
$capRate = New-TimeSpan -Minutes 5

foreach($camera in $cameras)
{
    New-Timelapse -Camera $camera -Name ($name -f $camera) -Start $start -End $end -Framerate 10 -CaptureRate $capRate -MissingFrames Duplicate -SolarNoon -Longitude -55.55555
}