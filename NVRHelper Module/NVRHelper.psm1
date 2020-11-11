$script:SessionType = $null
$script:BlueIrisSession = $null
$script:BlueIrisConnected = $false
$script:BlueIrisUri = $null
$script:BlueIrisCreds = $null
$script:BlueIrisServer = $null
$script:AgentDVRServer = $null
$script:AgentDVRConnected = $false
$script:AgentDVRUri = $null
$script:InternalDebug = $false

#region Generic external cmdlets
function Get-NVRCamera
{
    [CmdletBinding(DefaultParameterSetName="default")]
    param
    (
        [Parameter(Position=0)]
        [String]$camera
    )

    if($null -eq $script:SessionType)
    {
        Write-Warning "Not connected to any sources! Use a Connect-NVR* cmdlet."
    }

    if($script:SessionType -eq "BlueIris")
    {
        $cameras = $null
        if($null -eq $camera -or $camera.Length -eq 0)
        {
            $cameras = GetAllBlueIrisCameras
        }
        else
        {
            $cameras = GetSingleBlueIrisCamera $camera
        }

        return $cameras
    }

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
}

function New-NVRSnapshot
{
    [CmdletBinding(DefaultParameterSetName="default")]
    param
    (
        [Parameter(ParameterSetName="singleCameraByString",Mandatory=$true,Position=0)]
        [String]$camera,
        [Parameter(ParameterSetName="pipelineCamera",Mandatory=$true,ValueFromPipeline)]
        [PSCustomObject[]] $cameras
    )

    begin
    {
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq "singleCameraByString")
        {
            if($script:SessionType -eq "BlueIris")
            {
                TakeBlueIrisSnapshot $camera
            }
            elseif($script:SessionType -eq "AgentDVR")
            {
                TakeAgentDVRSnapshot (GetSingleAgentDVRCamera $camera)
            }
        }
        elseif($PSCmdlet.ParameterSetName -eq "pipelineCamera")
        {
            if($_.PSObject.TypeNames -contains "nvrCamera")
            {
                if($_.CameraType -eq "BlueIris")
                {
                    TakeBlueIrisSnapshot $_.Name
                }
                elseif($_.CameraType -eq "AgentDVR")
                {
                    TakeAgentDVRSnapshot $_
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

    end
    {

    }
}
#endregion

#region Agent DVR external cmdlets

function Connect-NVRAgentDVR
{
    [CmdletBinding(DefaultParameterSetName="default")]
    param
    (
        [Parameter(ParameterSetName="default",Mandatory=$true)]
        [String]$server
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
        
        $nvrCamera.PSObject.TypeNames.Insert(0,"nvrCamera")

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
        $camera
    )
    
    $uri = $script:AgentDVRUri + ("grab.jpg?oid={0}&size={1}x{2}" -f $camera.AgentDVR_ID, $camera.Width, $camera.Height)
    $result = Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile ("$HOME\Desktop\{0}-{1}.jpg" -f $camera.AgentDVR_ID, (Get-Date).Ticks)
}
#endregion

#region BlueIris external cmdlets
function Connect-NVRBlueIris
{
    [CmdletBinding(DefaultParameterSetName="default")]
    param
    (
        [Parameter(ParameterSetName="default",Mandatory=$true)]
        [String]$server,
        [PSCredential]$credential
    )

    if($null -eq $credential)
    {
        $credential = Get-Credential
    }

    $script:BlueIrisCreds = $credential
    $script:BlueIrisServer = $server

    $login = @{"cmd" = "login"} | ConvertTo-Json
    $results = Invoke-WebRequest -Uri ($server + "/json") -Method "POST" -UseBasicParsing -Body $login
    $content = $results.Content | ConvertFrom-Json
    $session = $content.session
    
    $response = "{0}:{1}:{2}" -f $credential.UserName, $session, $credential.GetNetworkCredential().Password
    $utf8response = [System.Text.Encoding]::UTF8.GetBytes($response)
    $md5 = [System.Security.Cryptography.HashAlgorithm]::Create("MD5")
    $md5response = ([System.BitConverter]::ToString($md5.ComputeHash($utf8response))).ToLower().Replace("-","")

    $login = @{"cmd" = "login"; "session" = $session; "response" = $md5response} | ConvertTo-Json
    $results = Invoke-WebRequest -Uri ($server + "/json") -Method "POST" -UseBasicParsing -Body $login
    $content = $results.Content | ConvertFrom-Json

    if($content.result -eq "success")
    {
        $script:BlueIrisConnected = $true
        $script:BlueIrisSession = $session
        $script:SessionType = "BlueIris"
        $script:BlueIrisUri = $server + "/json"
    }
}
#endregion

#region BlueIris internal helpers

function ParseBlueIrisCameras
{
    param
    (
        [Parameter(ParameterSetName="default",Mandatory=$true,Position=0)]
        $biCameras
    )

    $nvrCameras = @()
    foreach($camera in $biCameras)
    {
        $nvrCamera = [PSCustomObject]@{
            CameraType = 'BlueIris'
            Name = $camera.optionValue
          }
        
        $nvrCamera.PSObject.TypeNames.Insert(0,"nvrCamera")

        $nvrCameras += $nvrCamera
    }

    return $nvrCameras
}

function GetSingleBlueIrisCamera
{
    [CmdletBinding(DefaultParameterSetName="default")]
    param
    (
        [Parameter(ParameterSetName="default",Mandatory=$true,Position=0)]
        [String]$camera
    )

    $allCameras = GetAllBlueIrisCameras
    foreach($biCamera in $allCameras)
    {
        if($biCamera.name -eq $camera)
        {
            return $biCamera
        }
    }
}

function GetAllBlueIrisCameras
{
    #Get all cameras
    $content = SendBlueIrisRequest -parameters @{"cmd" = "camlist"}
    $cameras = @()
    if($content.result -eq "success")
    {
        foreach($result in $content.data)
        {
            if($result.optionValue -ne "@Index" -and $result.OptionValue -ne "Index")
            {
                $cameras += (ParseBlueIrisCameras $result)
            }
        }
    }
    else 
    {
        Write-Warning "Failure to retrieve cameras!"
        Write-Warning $content
    }

    return $cameras
}


function ReconnectBlueIris
{
    $server = $script:BlueIrisServer
    $credentials = $script:BlueIrisCreds

    $login = @{"cmd" = "login"} | ConvertTo-Json
    $results = Invoke-WebRequest -Uri ($server + "/json") -Method "POST" -UseBasicParsing -Body $login
    $content = $results.Content | ConvertFrom-Json
    $session = $content.session
    
    $response = "{0}:{1}:{2}" -f $credentials.UserName, $session, $credentials.GetNetworkCredential().Password
    $utf8response = [System.Text.Encoding]::UTF8.GetBytes($response)
    $md5 = [System.Security.Cryptography.HashAlgorithm]::Create("MD5")
    $md5response = ([System.BitConverter]::ToString($md5.ComputeHash($utf8response))).ToLower().Replace("-","")

    $login = @{"cmd" = "login"; "session" = $session; "response" = $md5response} | ConvertTo-Json
    $results = Invoke-WebRequest -Uri ($server + "/json") -Method "POST" -UseBasicParsing -Body $login
    $content = $results.Content | ConvertFrom-Json

    if($content.result -eq "success")
    {
        $script:BlueIrisConnected = $true
        $script:BlueIrisSession = $session
        $script:SessionType = "BlueIris"
        $script:BlueIrisUri = $server + "/json"
    }
}

function TakeBlueIrisSnapshot
{
    [CmdletBinding(DefaultParameterSetName="default")]
    param
    (
        [Parameter(ParameterSetName="default",Mandatory=$true,Position=0)]
        [String]$camera
    )
    ReconnectBlueIris
    $session = $script:BlueIrisSession
    $uri = "http://" + $script:BlueIrisServer + "/admin?camera=$camera&snapshot&session=$session"
    
    $result = Invoke-WebRequest -Uri $uri -UseBasicParsing
}

function SendBlueIrisRequest
{
    [CmdletBinding(DefaultParameterSetName="default")]
    param 
    (
        [Parameter(ParameterSetName="default",Mandatory=$true)]
        [Hashtable]
        $parameters
    )

    $content = $null

    if($script:BlueIrisConnected)
    {
        ReconnectBlueIris

        if("session" -notin $parameters.Keys)
        {
            $parameters.Add("session", $script:BlueIrisSession)
        }

        $jsonParams = $parameters | ConvertTo-Json

        if($script:InternalDebug)
        {
            Write-Host "URI: " $script:BlueIrisUri
            Write-Host "JSON: " $jsonParams
        }

        $results = Invoke-WebRequest -Uri $script:BlueIrisUri -Method "POST" -UseBasicParsing -Body $jsonParams
        $content = $results.Content | ConvertFrom-Json
    }

    return $content
}
#endregion