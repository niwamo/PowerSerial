function Start-SerialSession {
    param(
        [System.IO.Ports.SerialPort]$Port,
        [System.IO.FileStream]$Log
    )
    [Console]::TreatControlCAsInput = $true
    $cmd = $false
    $inputHelpers = [Collections.Generic.Dictionary[ConsoleKey,String]]::new()
    @{
        "UpArrow"       = $([char]27 + '[A')
        "DownArrow"     = $([char]27 + '[B')
        "RightArrow"    = $([char]27 + '[C')
        "LeftArrow"     = $([char]27 + '[D')
        "F1"            = $([char]27 + 'OP')
        "F2"            = $([char]27 + 'OQ')
        "F3"            = $([char]27 + 'OR')
        "F4"            = $([char]27 + 'OS')
        "F5"            = $([char]27 + '[15~')
        "F6"            = $([char]27 + '[17~')
        "F7"            = $([char]27 + '[18~')
        "F8"            = $([char]27 + '[19~')
        "F9"            = $([char]27 + '[20~')
        "F10"           = $([char]27 + '[21~')
        "F11"           = $([char]27 + '[23~')
        "F12"           = $([char]27 + '[24~')
        "Delete"        = $([char]127)
        "Home"          = $([char]27 + '[H')
        "End"           = $([char]27 + '[F')
        "PageUp"        = $([char]27 + '[5~')
        "PageDown"      = $([char]27 + '[6~')
        "Insert"        = $([char]27 + '[2~')
    }.GetEnumerator() | ForEach-Object {
        $inputHelpers.Add($_.Key, $_.Value) 
    }
    # Handle data received
    $job = Register-ObjectEvent `
        -InputObject $port `
        -EventName DataReceived `
        -MessageData $port `
        -Action {
            $data = $port.ReadExisting()
            Write-Host $data -NoNewline
            if ($Log) {
                $Log.Write([char[]]$data, 0, $data.Length)
            }
        } 
    Write-Host "Starting Session. CTRL+A -> Z to exit"
    # output blank line as a way of requesting a prompt from remote system
    $port.WriteLine("")
    # intercept and handle input
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $char = $key.KeyChar
            if ($cmd) {
                if ($char -eq "z") {
                    # exit
                    Write-Host
                    break
                } 
                $cmd = $false
            } else {
                if ([byte]$key.KeyChar -eq 1) {
                    $cmd = $true
                } else {
                    if ($inputHelpers.Keys.Contains($key.Key)) {
                        $msg = $inputHelpers[$key.Key]
                    } else {
                        $msg = $key.KeyChar
                    }
                    $port.Write($msg)
                    if ($Log) {
                        $Log.Write($msg, 0, $msg.Length)
                    }
                }
            }
        }
        Start-Sleep -Milliseconds 1
    }
    # Cleanup
    Get-EventSubscriber | Where-Object SourceObject -eq $port | Unregister-Event
    $job.Dispose()
}

function New-SerialSession {
    param(
        [int]$COMPort,
        [int]$BaudRate,
        [string]$LogFile = $null,
        [System.IO.Ports.Parity]$Parity = "None",
        [int]$DataBits = 8,
        [System.IO.Ports.StopBits]$StopBits = "one"
    )
    if ($LogFile) {
        if($PWD.Provider.Name -eq 'Filesystem'){
            [System.Environment]::CurrentDirectory = $PWD
        }
        try {
            $global:log = [System.IO.File]::Open("Create", "Write")
        } catch {
            "Could not open the specified file or file already exists"
        }
    } else {
        $global:log = $null
    }
    # Input Validation for args not validated with built-in types
    $msg = "No input validation for BaudRate. Please make sure your selection" + `
        " is supported by the target device"
    Write-Warning $msg
    $portNames = [System.IO.Ports.SerialPort]::GetPortNames()
    if (! $portNames.Contains("COM$COMPort")) {
        throw "COM Port not available. Currently available ports: $portNames"
    }
    # Create the port
    $global:port = [System.IO.Ports.SerialPort]::new(
        "COM$COMPort", 
        $BaudRate,
        $Parity, 
        $DataBits, 
        $StopBits
    )
    # try opening, exit if it fails
    try { $port.Open() } catch { throw "Failed to open serial port" }
    # start the interactive session
    Start-SerialSession -Port $port -Log $log
    # Cleanup
    $port.Close()
    $log.Close()
}
