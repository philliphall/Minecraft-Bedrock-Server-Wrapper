###################################################
# Wrapper for Minecraft Bedrock Edition Server    
# 
#  1) Launch the server.
#  2) Prevent PC from sleeping.
#  3) Backup periodically (No shutdown necessary!)
#  4) Shut down server if no one online for xx min.
#  5) Automatically upgrade server on launch. (Since this script is written for home use, expectation isn't that the server runs for days on end.)
# 
# And maybe later...
#  1) Warn before shutdown. 
#  2) Incremental backup scheme
#  3) Timestamp logs and maybe even write to logfile
# 
# And maybe never...
#  1) Use the TypeScript / node.js API instead. https://learn.microsoft.com/en-us/minecraft/creator/documents/scriptingservers
#
#
# Known Issues
# - If someone logs onto the server before initial backup completes, they don't get counted as a logged in user, which may mean the script thinks no one is logged in and shuts down the server after idle timeout is reached. 
#
# I recommend running this with a .bat file containing:
#  powershell.exe -ExecutionPolicy Bypass -NoExit -File "C:\Minecraft Server\MinecraftServerLaunchWrapper.ps1"
#
###################################################

### Configuration Variables
$sleepSetting   = 10 # What should we reset the sleep timer to before we quit
$serverLocation = 'C:\Minecraft Server' # Directory where bedrock_server.exe lives
$backupLocation = 'C:\Minecraft Server Backups' # Directory to store backup files - should not be inside $serverLocation (or vice versa)
$backupMinutes  = 10 # How frequently after starting to create automatic backups
$maxBackups     = 90 # Maximum number of backup archives before oldest one gets deleted
$idleShutdown   = 10 # After how many minutes of no one being logged in should we stop the server
$servercolor    = "Gray" # Just text color in the console, no biggie.
$scriptcolor    = "Green"


### Initialize Variables
$processObj  = New-Object System.Diagnostics.Process # 
$task        = $null # This will be used for asynchronous reading of the stdout stream.
$errortask   = $null # This will be used for asynchronous reading of the stderr stream.
$backupTimer = New-Object -TypeName System.Diagnostics.Stopwatch
$idleTimer   = New-Object -TypeName System.Diagnostics.Stopwatch
$onlineusers = 0 # Track how many people are logged in for purposes of idle shutdown timer.
$ErrorActionPreference = "Continue" # Should be default anyway, but just in case.


### Setting Log Information 
if(!(Test-Path -path "$backupLocation\logs")){
    Write-Host "Didn't find the Log folder. Creating it now"
    $null = New-Item -Path "$backupLocation\logs" -ItemType Directory
}
$Now = get-date
$LogFile = "$backupLocation\logs\" + $Now.ToString("yyyy-MM-dd-HH-mm-ss") + "-minecraft-wrapper-script.log" # Defining Log name and path
Start-Transcript -Path $LogFile # Starting the LOG
$DebugPreference = 'SilentlyContinue'
$WarningPreference = 'Continue'
$VerbosePreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'


### Main
function MAIN {
    
    # Update Server Version First
    $updateStatus = Update-Server

    # Launch Server
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "$serverLocation\bedrock_server.exe"
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardInput = $true
        $pinfo.UseShellExecute = $false
    $processObj.StartInfo = $pinfo
    $processObj.Start() | Out-Null

    # Wait until fully running
    for () {
        $line = $processObj.StandardOutput.ReadLine() # Not using Async here because I want to block until the server is really running. Doing this runs the risk of hanging my script if it doesn't launch properly.
        Write-Host $line -ForegroundColor $servercolor
        if ($line -match "Server started.") {
            break
        }
    }
    $idleTimer.Start()
    Write-Host "LaunchWrapper identified server successful launch." -ForegroundColor $scriptcolor

    # Add a helper message for server info
    $ip = (Get-NetIPAddress | Where-Object {$_.SuffixOrigin -eq "Dhcp" -and $_.AddressFamily -eq "IPv4"}).IPAddress
    $temp = Select-String -path "$serverLocation\server.properties" -Pattern "server-name=(.+)" -AllMatches
    $serverName = $temp.Matches.Groups[1].value
    $temp = Select-String -path "$serverLocation\server.properties" -Pattern "server-port=([0-9]+)" -AllMatches
    $port = $temp.Matches.Groups[1].value
    Write-Host "Server Name: $serverName" -ForegroundColor $scriptcolor
    Write-Host "Server IP:   $ip" -ForegroundColor $scriptcolor
    Write-Host "Server Port: $port" -ForegroundColor $scriptcolor

    # This is how we can send and receive commands to the server
    $streamWriter = $processObj.StandardInput
    # Then use $streamWriter.WriteLine("text here")
    $task = $processObj.StandardOutput.ReadLineAsync() # Begins listening, will check for content later
    $errortask = $processObj.StandardError.ReadLineAsync() # Same.

    # Prevent sleep
    & Powercfg /Change standby-timeout-ac 0

    # Initial backup and timer start
    $task = Create-Backup # Because this is easier than doing it on exit... trying to catch all the ways that could happen.
    $backupTimer.Start()
    
    # Process monitoring loop
    while ($processObj.HasExited -eq $false) { # Apparently .Responding is not reliable.
        
        # Look for user input
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $key = $key.Key
            if ($key -eq "F12") {
                Write-Host "Enter a command to send the server: " -NoNewline -ForegroundColor $scriptcolor
                $command = Read-Host
                $streamWriter.WriteLine($command)
            }
            else {
                Write-Host "You hit the key $key. If you want to send the server commands, press F12 first." -ForegroundColor $servercolor
            }
        }


        # Process anything incomming from the server.
        Start-Sleep -Milliseconds 2
        while ($task.IsCompleted) {
            Write-Host $task.Result -ForegroundColor $servercolor
        
            # Is it a log in?
            if ($task.Result -match "Player connected") {
                $onlineusers += 1
                $idleTimer.Reset()
                Write-Host "Logged in users: $onlineusers" -ForegroundColor $scriptcolor
            }

            # Is it a log out?
            elseif ($task.Result -match "Player disconnected") {
                $onlineusers -= 1
                if ($onlineusers -le 0) {
                    $idleTimer.Start()
                    Write-Host "Logged in users: $onlineusers" -ForegroundColor $scriptcolor
                }
            }
            
            $task = $processObj.StandardOutput.ReadLineAsync()
            Start-Sleep -Milliseconds 2
        }


        # If time for a periodic backup
        if ($backupTimer.Elapsed.Minutes -ge $backupMinutes) {
            $task = Create-Backup
            $backupTimer.Restart()        
        }


        # Idle check
        if ($idleTimer.Elapsed.Minutes -eq ($idleShutdown -1)) {
            Write-Host "No one has been logged in for $($idleTimer.Elapsed.Minutes) minutes. Shutting down in 1 minute!" -ForegroundColor $scriptcolor
        }
        if ($idleTimer.Elapsed.Minutes -ge $idleShutdown) {
            Write-Host "No one has been logged in for $($idleTimer.Elapsed.Minutes) minutes. Stopping the server." -ForegroundColor $scriptcolor
            $streamWriter.WriteLine("stop")
        }


        # Dump stderr
        while ($errortask.IsCompleted) {
            Write-Host $errortask.Result -ForegroundColor Red        
            $errortask = $processObj.StandardError.ReadLineAsync()
            Start-Sleep -Milliseconds 2
        }

        # Reduce burden of this loop
        Start-Sleep -Seconds 1
    }

    # Process no longer running
    Write-Host "Server has exited." -ForegroundColor $scriptcolor
    & Powercfg /Change standby-timeout-ac $sleepSetting
    Write-Host "Computer sleep setting reset to $sleepSetting minutes." -ForegroundColor $scriptColor
    Stop-Transcript

}


### Common Functions

function Create-Backup {
    Write-Host "Time for a backup..." -ForegroundColor $scriptcolor

    try {
        # We need the server to be prepared to take a backup. Send command and await confirmation.
        $held = 0
        $streamWriter.WriteLine("save hold")
        while ($held -eq 0) { # Wait to get confirmation of "Saving..."
            while ($task.IsCompleted -eq $false) { Start-Sleep -Milliseconds 1 }
            Write-Host $task.Result -ForegroundColor $servercolor
            if ($task.Result -match 'Saving') { 
                $held = 1
            }
            $task = $processObj.StandardOutput.ReadLineAsync()
        }
        
        # Now we need the list of files to backup. Similarly, send command and await confirmation.
        Start-Sleep -Milliseconds 50 # Because I was getting a "A previous save has not been completed." error. 
        $returnstring = ""
        $streamWriter.WriteLine("save query")
        while ($returnstring -eq "") {
            while ($task.IsCompleted -eq $false) { Start-Sleep -Milliseconds 1 }
            Write-Host $task.Result -ForegroundColor $servercolor
            if ($task.Result -match 'Data saved') {
                # The next line should be what we want. 
                $task = $processObj.StandardOutput.ReadLineAsync()
                while (-not $task.IsCompleted) { Start-Sleep -Milliseconds 1 }
                Write-Host $task.Result -ForegroundColor $servercolor
                $returnstring = $task.Result
            }
            elseif ($task.Result -match 'save has not') { # Because I was getting a "A previous save has not been completed." error.
                Start-Sleep -Seconds 1
                $streamWriter.WriteLine("save query")
            }
            $task = $processObj.StandardOutput.ReadLineAsync() 
        }
        
        # Process the list of files to backup.
        Write-Host "Backing up files..." -ForegroundColor $scriptColor
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH_mm"
        $null = mkdir $backupLocation\$timestamp
        foreach ($line in $returnstring -split ', ') {
            $file = ""
            $file = ($line -split ':')[0] -replace '/', '\'
            $filepath = $serverLocation+"\worlds\"+$file
            $null = New-Item -ItemType File -Path "$backupLocation\$timestamp\$file" -Force # Touch to force subdirectory creation
            $null = Copy-Item -Path $filepath -Destination $backupLocation\$timestamp\$file
        }
        
        # Set the server back to normal mode.
        Write-Host "Resuming server normal operation." -ForegroundColor $scriptColor
        $streamWriter.WriteLine("save resume")
        while ($held -eq 1) { # Wait to get confirmation of "Changes to the world are resumed."
            while ($task.IsCompleted -eq $false) { Start-Sleep -Milliseconds 1 }
            Write-Host $task.Result -ForegroundColor $servercolor
            if ($task.Result -match 'are resumed') { 
                $held = 0
            }
            $task = $processObj.StandardOutput.ReadLineAsync()           
        }

        # Compress and clean up
        Write-Host "Compressing and cleaning up." -ForegroundColor $scriptColor
        Compress-Archive -Path $backupLocation\$timestamp\* -DestinationPath ($backupLocation + "\" + $timestamp + ".zip")
        Remove-Item -LiteralPath $backupLocation\$timestamp -Force -Recurse
        $items = Get-ChildItem $backupLocation
        if ($items.Count -gt $maxBackups) {
            $items | Sort-Object LastWriteTime -Descending | Select-Object -Last 1 | Remove-Item
        }
        
        Write-Host "Backup completed." -ForegroundColor $scriptcolor
    }
    catch {
        Write-Host "Backup had an issue!! Continuing anyway." -ForegroundColor Red
    }
    return $task # Because of scope issues I assume. This was causing a persistent error before capturing and returning this. 
}



# Server version update
function Update-Server {
    <#
        .SYNOPSIS
            Script for automating Minecraft Bedrock Server Updating for Windows
            Adapted from https://github.com/XingLii/minecraft-bedrock-windows-updater-powershell-script/blob/main/Update_Bedrock_Server.ps1
        .DESCRIPTION
            Script which will automatically retrieve the newest version of Bedrock Minecraft.
            Then download it and install the newest version. 
    #>

    #Setup Folders
    if(!(Test-Path -path "$backupLocation/Downloads")){
        Write-Host "Didn't find the Download folder. Creating it now" -ForegroundColor $scriptColor
        $null = New-Item -Path "$backupLocation/Downloads" -ItemType Directory
    }

    #Create First Time Version File
    if(!(Test-Path "$backupLocation/version.txt")){
        Write-Host "Didn't find the Version File. Creating it now" -ForegroundColor $scriptColor
        $null = New-Item "$backupLocation/version.txt" -ItemType File -Force
    }

    # Currrent version is based on last time this script downloaded a new one.
    $local_version = Get-Content -Path "$backupLocation/version.txt"
    Write-Host "Current version found: $($local_version)" -ForegroundColor $scriptColor

    # Online update available?
    Write-Host "Checking for availabe version online" -ForegroundColor $scriptColor
    try {
        $request = Invoke-Webrequest -Uri "https://www.minecraft.net/en-us/download/server/bedrock" -UseBasicParsing
        $download_link = $request.Links | ? class -match "btn" | ? href -match "bin-win/bedrock" | select -ExpandProperty href
        $online_version = $download_link.split("/")[5].split("-")[2].replace(".zip", "")
        Write-Host "Online version found: $($online_version)" -ForegroundColor $scriptColor
    }
    catch {
        Write-Host -Message "Unable to get online version. Abandoning update attempt." -ForegroundColor Red
        return "Error"
    }


    # If already up to date. 
    if ($local_version -eq $online_version) {
        Write-Host "Local version and Online version are identical." -ForegroundColor $scriptColor
	    return "Already current."
    }


    # Else, local version is different and we need to update the server
    else {
        Write-Host "There are different Online and Local versions." -ForegroundColor $scriptColor
        
        try {
            # Stopping the Minecraft server
            if ((get-process "bedrock_server.exe" -ea SilentlyContinue) -ne $Null) {
                Write-Warning -Message "Looks like an instance of the servier is already running! Stopping the Minecraft service..."
                Get-Process | ? {$_.ProcessName -eq "bedrock_server.exe"} | Stop-Process -Force  # Fore Stop Minecraft Server
                start-sleep -s 2
            }

            # Backup the Minecraft server
            Write-Host "Initiating server backup" -ForegroundColor $scriptColor
            if(!(Test-Path -path "$backupLocation\ServerVersionBackup")){
                Write-Host "Didn't find the backup folder. Creating it now" -ForegroundColor $scriptColor
                New-Item -Path "$backupLocation\ServerVersionBackup" -ItemType Directory
            }
            Write-Host "Copying the current server into the backup folder" -ForegroundColor $scriptColor
            $backup_folder = "$backupLocation\ServerVersionBackup\bedrock-server-$($local_version)"
            Copy-Item -Path "$serverLocation" -Destination $backup_folder -recurse
            #Start-Sleep -s 5

            # Removing old server files from $serverLocation
            #Write-Warning -Message "Removing the current version of the server!"
            #Remove-Item -Path "$serverLocation/bedrock-server" -Recurse -Force

    
            # Downloading and Extracting the new version of Minecraft
            Write-Host "Downloading the new version of the server" -ForegroundColor $scriptColor
            Invoke-WebRequest -Uri $download_link -OutFile "$backupLocation\Downloads\bedrock-server.zip" -UseBasicParsing
            Write-Host "Expanding the folder to the server folder" -ForegroundColor $scriptColor
            #[System.IO.Compression.ZipFile]::ExtractToDirectory("$($backupLocation)\Downloads\bedrock-server.zip", $serverLocation, [boolean]$true) # Doesn't work - requires .NET Core version not included in PS any more.
            Expand-Archive -Path "$backupLocation\Downloads\bedrock-server.zip" -DestinationPath $serverLocation -Force


            # Copying old Configurations files to the new server
            #Write-Host "Copying world files into new server"
            #Copy-Item "$backup_folder/worlds" -Destination $serverLocation -Recurse -Force
            Write-Host "Copying permissions file into new server" -ForegroundColor $scriptColor
            Copy-Item "$backup_folder/permissions.json" -Destination $serverLocation -Force
            Write-Host "Copying server properties file into new server" -ForegroundColor $scriptColor
            Copy-Item "$backup_folder/server.properties" -Destination $serverLocation -Force
            Write-Host "Copying allowlist file into new server" -ForegroundColor $scriptColor
            Copy-Item "$backup_folder/allowlist.json" -Destination $serverLocation -Force    
            #Write-Host "Copying Resource Packs"
            #Copy-Item "$backup_folder/resource_packs" -Destination $serverLocation -Recurse -Force
            #Write-Host "Copying this script into new server"
            #Copy-Item "$backup_folder/MinecraftServerLaunchWrapper.ps1" -Destination $serverLocation -Force


            # Creating new Version text file
            Write-Host "Creating a new version.txt file" -ForegroundColor $scriptColor
            $version_file = "$backupLocation\version.txt"
            $null = New-Item $version_file -ItemType File -Force
            Add-Content -Path $version_file -Value "$($online_version)" -NoNewline


            # Compressing the backup server folder
            Write-Host "Compressing the backed up server version to conserve space" -ForegroundColor $scriptColor
            $string = "$($backup_folder).zip"
            [IO.Compression.ZipFile]::CreateFromDirectory( $backup_folder, $string, 'Fastest', $false )

            # Removing the old uncompressed server files
            Write-Host "Remove uncompressed version of backup server" -ForegroundColor $scriptColor
            if(Test-Path "$($backup_folder).zip"){
                Remove-Item -Path $backup_folder -Recurse -Force
            }


            # Cleaning up downloaded files
            Write-Host "Remove temp download files" -ForegroundColor $scriptColor
            if(Test-Path "$serverLocation\Downloads\bedrock-server.zip"){
                Remove-Item -Path "$serverLocation\Downloads\bedrock-server.zip" -Force
            }


            # All done
            Write-Host "Server update complete." -ForegroundColor $scriptColor
            return "Updated to $online_version"
        }
        
        catch {
            Write-Warning -Message "Attempt to update had an error."
            Write-Host $error -ForegroundColor Red
            return "Error"
        }
    }

    return "Shouldn't get here."
}


MAIN