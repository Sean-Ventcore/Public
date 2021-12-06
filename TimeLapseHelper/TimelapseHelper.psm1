$script:Config = Import-PowerShellDataFile ($PSScriptRoot + "/TimelapseHelperConfig.psd1")

$script:SessionType = $null
$script:AgentDVRServer = $null
$script:AgentDVRConnected = $false
$script:AgentDVRUri = $null
$script:InternalDebug = $false

#region Generic external cmdlets
function Get-NVRCamera
{
    #Gets all cameras (or one if a name is specified), useful for verifying connectivity/resolution,
    #But mostly for pipelining to New-NVRSnapshot.
    [CmdletBinding()]
    param
    (
        [Parameter(Position=0)]
        [String]$Camera
    )

    if($script:SessionType -eq "AgentDVR")
    {
        $cameras = $null
        if($null -eq $camera -or $camera.Length -eq 0)
        {
            $cameras = GetAllAgentDVRCameras
        }
        else
        {
            $cameras = GetSingleAgentDVRCamera $camera
        }

        return $cameras
    }
    else
    {
        Write-Warning "Not connected to any sources! Use a Connect-NVR* cmdlet."    
    }
}

function New-Timelapse
{
    #Creates a timelapse output movie based on the raw data captured via New-NVRSnapshot
    #(or any other source with matching filenames in the location specified in TimelapseHelper.psd1)
    [CmdletBinding()]
    param
    (
        #The name of the camera, used to select the correct frames
        [Parameter(Mandatory=$true)]
        [String]$Camera,
        
        #The name of the output timelapse movie (without the file extension)
        [Parameter(Mandatory=$true)]
        [String]$Name,
        
        #The start time for what images to include in the timelapse
        [Parameter(Mandatory=$true)]
        [DateTime]$Start,
        
        #The end time for what images to include in the timelapse
        [Parameter(Mandatory=$true)]
        [DateTime]$End,
        
        #The framerate of the output timelapse movie
        [Parameter(Mandatory=$true)]
        [int]$Framerate,
        
        #Optional - specify to limit image inclusion to the specified frequency
        #(otherwise, all images within the times specified will be included)
        #This is assumed to not be any finer grained than seconds - a timelapse
        #with more than a frame per second is just a normal video.
        [Parameter(Mandatory=$true, ParameterSetName="SpecificFrequency")]
        [TimeSpan]$Frequency,
        
        #Optional - instead of frequency, use -SolarNoon to pick a daily frame from solar noon
        #based on the date (from Start through End) and Longitude.
        #For timezones whose offsets contain minutes as well as hours, this will currently return
        #slightly incorrect results.
        [Parameter(Mandatory=$true, ParameterSetName="SolarNoon")]
        [Switch]$SolarNoon,

        [Parameter(Mandatory=$true, ParameterSetName="SolarNoon")]
        [Double]$Longitude,

        #Optional - specify to indicate the capture rate of images in the raw data
        #This will allow the script to warn about potential issues when the capture
        #rate and frequency don't align, as well as to better calculate the level
        #of acceptable fuzziness on matching timestamps.
        #Like the frequency, this shouldn't be specified in anything smaller than seconds.
        [Parameter()]
        [TimeSpan]$CaptureRate,

        #Optional - specify the behavior to use when there's a missing frame in the timelapse
        #Skip - drops the frame from the timelapse, causing a jump forward in time but ensuring that each frame is unique and valid. This is the default behavior.
        #Blank - replaces missing frames with a monochrome gray image, which makes missing frames obvious but retains the tempo and length of the timelapse
        #Duplicate - re-uses the previous frame for any missing frames, which preserves the tempo/time and avoids the jarring switch to a blank frame,
        # at the cost of masking the fact that there's missing data there.
        [Parameter()]
        [ValidateSet("Skip","Blank","Duplicate")]
        [String]$MissingFrames,

        #Optional - specify the start/end time during the day to filter frames by
        #to exclude long periods of dead time, i.e. for capturing work done during the day
        #This will be ignored if SolarNoon is used
        [Parameter()]
        [DateTime]$DailyStart,
        [Parameter()]
        [DateTime]$DailyEnd
    )

    if($env:path -notlike "*ffmpeg*")
    {
        $env:path = $env:path + ";" + $script:Config["ffmpegPath"]
    }

    $pattern = $camera+"-*.jpg"
    #$files = Get-ChildItem $pattern -Path $script:Config["snapshotPath"]
    if($SolarNoon)
    {
        $pattern = "Solar{0}-*.jpg" -f $camera
    }

    $allFiles = Get-ChildItem -Path $script:Config["snapshotPath"] $pattern | Sort-Object CreationTime | Select-Object Name,FullName,CreationTime
    
    $tempFile = New-TemporaryFile
    $filelistLine = "file '{0}'"
    
    #If EndTime is before or at StartTime, halt execution
    if($End -le $Start)
    {
        throw "Error! Specified End time is not after specified Start time."
    }

    #Determine max acceptable fuzziness - how far outside of the target time we're willing to flex
    #in order to find a frame. These can be tweaked for desired behavior, but as a baseline it should
    #be slightly less than the frame capture rate of the raw data (so we don't skip an entire interval and pick
    #a previous frame, i.e. if the frame that should have started the timelapse wasn't created.)

    #Assuming the frequency (of frames to be included in the timelapse) is longer than the capture rate
    #(of frames in the raw data), which will cause other issues if it's not true, that's all we need to
    #do, but since the capture rate isn't a required parameter, we'll also do a fallback calculation
    #if the frequency was specified and capture rate wasn't. In those cases, half the frequency seems
    #like a safe starting point.

    #If neither is specified, we'll just pick the closest frame within the specified range 
    #(even if there's a good frame a few milliseconds outside the specified range, so specifying
    #either the frequency or capture rate is recommended, outside of very basic testing.)
    $maxFuzziness = New-TimeSpan -Seconds 0

    if($null -ne $CaptureRate)
    {
        $maxFuzziness = New-TimeSpan -Seconds ($CaptureRate.TotalSeconds * 0.9)
        Write-Verbose "CaptureRate specified, maxFuzziness is now $maxFuzziness"
    }
    elseif($null -ne $Frequency)
    {
        $maxFuzziness = New-TimeSpan -Seconds ($Frequency.TotalSeconds / 2)
        Write-Verbose "Frequency specified, maxFuzziness is now $maxFuzziness"
    }

    $fuzzyStart = $Start - $maxFuzziness
    $fuzzyEnd = $End + $maxFuzziness

    $files = $allFiles | where {$_.CreationTime -ge $fuzzyStart -and $_.CreationTime -le $fuzzyEnd}

    Write-Host ("Files selected: " + $files.Count)

    #If frequency and capture rate are both specified, warn if the frequency doesn't divide evenly
    #into the capture rate - i.e. if we're capturing frames every 5 minutes, a timelapse of frames
    #every 5 or 10 or 60 minutes would be fine, but every 7 minutes wouldn't align with the available data.

    if($null -ne $Frequency -and $null -ne $CaptureRate)
    {
        $alignment = $Frequency.TotalSeconds / $CaptureRate.TotalSeconds

        if($alignment -ne [Math]::Truncate($alignment))
        {
            Write-Warning "Frequency is misaligned with capture rate! Results may be irregular, regenerating the timelapse with a corrected frequency is recommended."
            Write-Warning "Press Enter to continue generation, or Ctrl-C to cancel."
            Read-Host
        }
    }

    #compare available data to requested frequency of frames in timelapse, if a frequency is specified
    #if no frequency is specified, there's no baseline for comparison, so we'll skip this and simply
    #use all available frames without worrying about time range between frames or gaps
    if($null -ne $Frequency)
    {
        $times = Get-AverageFileTimeInterval -path $script:Config["snapshotPath"] -Pattern $pattern -Start $start -End $end

        #metric to indicate if the available frames are enough to fill in the requested frequency or not
        #i.e.: if we're taking snapshots every 5 minutes and generate a timelapse with frames every 10 minutes,
        #this will be around 2.0 if every snapshot was successful. Around 1 means the frequency of both is
        #roughly the same. Anything much below that indicates that we're trying to make a timelapse with more
        #frames than we really have. I.e. a value of 0.5 might happen either because we're generating frames every 10 minutes
        #but trying to make a timelapse with frames from every 5 minutes, or because the camera was offline for half the period.
        #The $maxMissingFrames metric below will help indicate if it's a singular outage (if the camera is offline intermittently,
        #that will look very similar to not taking snapshots frequently enough, depending on the details of the situation.)
        $availabilityRatio = $Frequency.TotalSeconds / $times.Average
    
        if($availabilityRatio -ge 0.99)
        {
            Write-Verbose "Availability of frames in time range vs. frequency is good: $availabilityRatio"
        }
        elseif($availabilityRatio -lt 0.5)
        {
            Write-Error "Availability of frames in time range vs. frequency is bad: $availabilityRatio"
        }
        elseif($availabilityRatio -lt 0.8)
        {
            Write-Warning "Availability of frames in time range vs. frequency is poor: $availabilityRatio"
        }
        elseif($availabilityRatio -lt 0.99)
        {
            Write-Verbose "Availability of frames in time range vs. frequency is less than ideal: $availabilityRatio"
        }
        else
        {
            Write-Error "Availability of frames in time range vs. frequency is unexpected: $availabilityRatio"
        }
    
        #This will give us the longest period in which no frames are available, i.e. if a camera or the snapshot computer is offline
        #or otherwise fails to generate an image. If this is long we'll either have a sudden jump in time, or need to fill in with either
        #blank or duplicate frames.
        $maxMissingFrames = $times.Maximum / $Frequency.TotalSeconds
    
        if($maxMissingFrames -ge 2)
        {
            Write-Warning "Largest detected sequence of missing frames: $maxMissingFrames"
        }
        else 
        {
            Write-Host "Largest detected sequence of missing frames: $maxMissingFrames"    
        }
    }
    
    if($null -eq $Frequency)
    {
        Write-Verbose "Frequency is null"
        if($PSCmdlet.ParameterSetName -eq "SolarNoon")
        {
            Write-Verbose "Solar Noon Timelapse"
            $currentDay = $Start
            $oldFile = $null
            $file = $null

            Write-Verbose "Solar Noon Timelapse, current day: $currentDay"

            do
            {
                $currentDaySolarNoon = Get-SolarNoon -Date $currentDay -Longitude $Longitude
                Write-Verbose "Solar Noon Timelapse, solar noon: $currentDaySolarNoon"

                $oldFile = $file

                $file = Get-ClosestFrame -Files $files -TargetTime $currentDaySolarNoon -Range (New-TimeSpan -Hours 1)
                
                if($null -ne $file)
                {
                    Write-Verbose "Solar Noon Timelapse, adding file: $file"
                    Add-Content -Path $tempFile -Value ($filelistLine -f $file.FullName)
                }

                $currentDay = $currentDay.AddDays(1)
                $dayDiff = ($End - $currentDay).Days
            }
            until($dayDiff -eq -1)
        }
        else
        {
            #Frequency not specified, so we can apply some fuzziness to the time range but
            #still use all frames. If capture rate wasn't specified, the fuzziness will be 0.

            Write-Verbose "All-Inclusive Timelapse"

            foreach($file in $files)
            {
                $fileDate = [DateTime]::ParseExact($file.Name.Split('-')[1].Split('.')[0],"yyyyMMddHHmm",$null)

                if($fileDate -ge ($start - $maxFuzziness) -and $fileDate -le ($end + $maxFuzziness))
                {
                    Write-Verbose "All-Inclusive Timelapse, adding file: $file"
                    if(($DailyStart -eq $null -or $fileDate.TimeOfDay -ge $DailyStart.TimeOfDay) -and ($DailyEnd -eq $null -or $fileDate.TimeOfDay -le $DailyEnd.TimeOfDay))
                    {
                        Add-Content -Path $tempFile -Value ($filelistLine -f $file.FullName)
                    }
                }
            }
        }
    }
    else
    {
        #Frequency specified, so we can apply some fuzziness and also need to select only
        #matching frames

        $currentTime = $Start
        $file = $null
        $oldFile = $null

        do
        {
            $oldFile = $file
            $file = Get-ClosestFrame -Files $files -TargetTime $currentTime -Range $maxFuzziness
            
            if($null -ne $file)
            {
                $fileDate = [DateTime]::ParseExact($file.Name.Split('-')[1].Split('.')[0],"yyyyMMddHHmm",$null)

                if(($DailyStart -eq $null -or $fileDate.TimeOfDay -ge $DailyStart.TimeOfDay) -and ($DailyEnd -eq $null -or $fileDate.TimeOfDay -le $DailyEnd.TimeOfDay))
                {
                    Add-Content -Path $tempFile -Value ($filelistLine -f $file.FullName)
                }
                
            }
            else
            {
                Write-Verbose "Missing frame at $currentTime"

                if($null -eq $MissingFrames -or $MissingFrames -eq "Skip")
                {
                    
                }
                elseif($MissingFrames -eq "Duplicate") 
                {
                    if($null -ne $oldFile)
                    {
                        $fileDate = [DateTime]::ParseExact($oldFile.Name.Split('-')[1].Split('.')[0],"yyyyMMddHHmm",$null)
                        if(($DailyStart -eq $null -or $fileDate.TimeOfDay -ge $DailyStart.TimeOfDay) -and ($DailyEnd -eq $null -or $fileDate.TimeOfDay -le $DailyEnd.TimeOfDay))
                        {
                            Add-Content -Path $tempFile -Value ($filelistLine -f $oldFile.FullName)
                        }
                    }
                }
                elseif($MissingFrames -eq "Blank")
                {
                    throw "Not yet implemented!"
                }
            }

            $currentTime = $currentTime + $Frequency
        }
        while($currentTime -le $End)
    }

    ffmpeg.exe -r $Framerate -f concat -safe 0 -i $tempFile.FullName -c:v mjpeg ($script:Config["timelapsePath"] + $name + ".mov")

    ##cropping version - commented out, need to plumb in parameters to make it available
    # $x1 = 1411
    # $y1 = 212
    # $x2 = 1569
    # $y2 = 559
    
    # $width = [Math]::Abs($x2 - $x1)
    # $height = [Math]::Abs($y2 - $y1)

    # ffmpeg.exe -r $Framerate -f concat -safe 0 -i $tempFile.FullName -filter:v ("crop={0}:{1}:{2}:{3}" -f $width, $height, $x1, $y1) -c:v mjpeg ($script:Config["timelapsePath"] + $name + ".mov")
    
    Write-Debug "$tempFile will be deleted now"
    #Remove-Item $tempFile
}

function Get-SolarNoon
{
    #Gets the time of solar noon (sun directly overhead) based on the longitude and date
    #calculations as per https://www.esrl.noaa.gov/gmd/grad/solcalc/solareqns.PDF
    #Potentially useful for a daily timelapse at "noon" to avoid shadows shifting as
    #solar noon vs. nominal noon shift in relation to each other over the month/year
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [Double]$Longitude,
        [Parameter(Mandatory=$true)]
        [DateTime]$Date
    )

    $fYear = ((2*[Math]::PI)/365) * ($Date.DayOfYear - 1)
    $eqTime = 229.18*(0.000075 + 0.001868*[Math]::Cos($fYear) - 0.032077 * [Math]::Sin($fYear) - 0.014615 * [Math]::cos(2*$fYear) - 0.040849 * [Math]::Sin(2*$fYear) )
    $timeOffset = $eqTime + 4*$Longitude - 60*($date.ToString("zz"))

    $noonifiedTime = $Date.AddHours(12 - $Date.Hour).AddMinutes(-1*$Date.Minute).AddSeconds(-1*$Date.Second).AddMilliseconds(-1*$Date.Millisecond)
    $solarNoon = $noonifiedTime.AddMinutes(-1*$timeOffset)

    return $solarNoon
}

function Get-ClosestFrame
{
    #finds the image file in $Files closest to the $TargetTime (before or after), no further out than $Range
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        $Files,
        [Parameter(Mandatory=$true)]
        [DateTime]$TargetTime,
        [Parameter(Mandatory=$true)]
        [TimeSpan]$Range
    )

    $closest = $null
    $proximity = $Range

    $targetTimeUTC = $TargetTime.ToUniversalTime()

    foreach($file in $Files)
    {
        $fileDate = [DateTime]::ParseExact($file.Name.Split('-')[1].Split('.')[0],"yyyyMMddHHmm",$null)
        if($fileDate -le $targetTimeUTC)
        {
            $currentProximity = $targetTimeUTC - $fileDate
        }
        else
        {
            $currentProximity = $fileDate - $targetTimeUTC
        }
        
        if($currentProximity -le $Range -and $currentProximity -le $proximity)
        {
            $closest = $file
            $proximity = $currentProximity
        }
    }

    return $closest
}

function Get-AverageFileTimeInterval
{
    #returns info on the average, minimum, and maximum time interval between file creation dates
    #for files in $Path matching $Pattern, between the $Start and $End times
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [String]$Path,
        [Parameter(Mandatory=$true)]
        [String]$Pattern,
        [Parameter(Mandatory=$true)]
        [DateTime]$Start,
        [Parameter(Mandatory=$true)]
        [DateTime]$End
    )

    $files = Get-ChildItem -Path $path $pattern | Sort-Object CreationTime | Select-Object CreationTime
    $spans = @()

    $prevTime = $null
    foreach($file in $files)
    {
        $currTime = $file.CreationTime
        if($null -ne $prevTime)
        {
            if($prevTime -ge $Start -and $currTime -le $End)
            {
                $spans += ($currTime - $prevTime)
            }
        }

        $prevTime = $currTime
    }

    $measurement = $spans | Measure-Object -property TotalSeconds -Average -Minimum -Maximum
    
    return $measurement
}

function New-RTSPSnapshot
{
    param
    (
        [Parameter(Mandatory=$true)]
        [String]$Url,
        [Parameter(Mandatory=$true)]
        [String]$Name,
        [String]$Pattern
    )

    if($null -eq $Pattern -or $Pattern.Length -eq 0)
    {
        $Pattern = "{0}-{1}.jpg"
    }

    if($env:path -notlike "*ffmpeg*")
    {
        $env:path = $env:path + ";" + $script:Config["ffmpegPath"]
    }
    
    $out = ($script:Config["snapshotPath"] + ($pattern -f $Name, (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmm")))
    ffmpeg.exe -y -rtsp_transport tcp -i $Url -vframes 1 $out
}

function New-NVRSnapshot
{
    #Captures an image of the specified camera(s) current view, accepting either a single camera name
    #Or pipeline input from Get-NVRCamera
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName="singleCameraByString",Mandatory=$true,Position=0)]
        [String]$Camera,
        [Parameter(ParameterSetName="pipelineCamera",Mandatory=$true,ValueFromPipeline)]
        [PSCustomObject[]] $Cameras,
        [String]$Pattern
    )

    begin
    {
        if($null -eq $Pattern -or $Pattern.Length -eq 0)
        {
            $Pattern = "{0}-{1}.jpg"
        }
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq "singleCameraByString")
        {
            if($script:SessionType -eq "AgentDVR")
            {
                TakeAgentDVRSnapshot (GetSingleAgentDVRCamera $camera) $Pattern
            }
        }
        elseif($PSCmdlet.ParameterSetName -eq "pipelineCamera")
        {
            if($_.PSObject.TypeNames -contains "ipCamera")
            {
                if($_.CameraType -eq "AgentDVR")
                {
                    TakeAgentDVRSnapshot $_ $Pattern
                }
                else
                {
                    Write-Warning ("New-NVRSnapshot not implemented for " + $_.CameraType)
                }
            }
            else
            {
                Write-Warning "Invalid object type!"    
            }
        }
    }
}
#endregion

#region Agent DVR external cmdlets

function Connect-NVRAgentDVR
{
    #Saves connection info for an Agent DVR server (generally on the local network by IP.)
    #Prerequisite for using Get-NVRCamera or New-NVRSnapshot.
    [CmdletBinding(DefaultParameterSetName="default")]
    param
    (
        [Parameter(ParameterSetName="default",Mandatory=$true)]
        [String]$Server
    )

    $script:AgentDVRServer = $server
    $script:AgentDVRConnected = $true
    $script:SessionType = "AgentDVR"
    $script:AgentDVRUri ="http://$server/"
}

#endregion

#region Agent DVR internal helpers
function GetAllAgentDVRCameras
{ 
    $command = "command.cgi?cmd=getObjects"

    $results = Invoke-WebRequest -UseBasicParsing -Uri ($script:AgentDVRUri + $command)
    $content = ConvertFrom-Json $results.Content
    $cameras = @()
    
    foreach($object in $content.objectList)
    {
        if($object.typeID -eq 2)
        {
            $cameras += $object
        }
    }

    return (ParseAgentDVRCameras $cameras)
}

function GetSingleAgentDVRCamera
{
    [CmdletBinding(DefaultParameterSetName="default")]
    param
    (
        [Parameter(ParameterSetName="default",Mandatory=$true,Position=0)]
        [String]$camera
    )

    $allCameras = GetAllAgentDVRCameras
    foreach($agdCamera in $allCameras)
    {
        if($agdCamera.name -eq $camera)
        {
            return $agdCamera
        }
    }
}

function ParseAgentDVRCameras
{
    param
    (
        [Parameter(ParameterSetName="default",Mandatory=$true,Position=0)]
        $agdCameras
    )

    $nvrCameras = @()
    foreach($camera in $agdCameras)
    {
        $nvrCamera = [PSCustomObject]@{
            CameraType = 'AgentDVR'
            Name = $camera.name
            Height = $camera.data.mjpegStreamHeight
            Width = $camera.data.mjpegStreamWidth
            AgentDVR_ID = $camera.id
          }
        
        $nvrCamera.PSObject.TypeNames.Insert(0,"ipCamera")

        $nvrCameras += $nvrCamera
    }

    return $nvrCameras
}

function TakeAgentDVRSnapshot
{
    [CmdletBinding(DefaultParameterSetName="default")]
    param
    (
        [Parameter(ParameterSetName="default",Mandatory=$true,Position=0)]
        $camera,
        [Parameter(ParameterSetName="default",Mandatory=$true,Position=1)]
        $pattern
    )
    
    $uri = $script:AgentDVRUri + ("grab.jpg?oid={0}&size={1}x{2}" -f $camera.AgentDVR_ID, $camera.Width, $camera.Height)
    $result = Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile ($script:Config["snapshotPath"] + ($pattern -f $camera.AgentDVR_ID, (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmm")))
}
#endregion