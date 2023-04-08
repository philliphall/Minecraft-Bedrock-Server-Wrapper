# Minecraft-Bedrock-Server-Wrapper
Wrapper script for Minecraft Bedrock Server running on Windows, designed for at-home, private use. Includes frequent backups, auto update, auto idle server stopping, and prevents the computer from sleeping while active.

MinecraftServerLaunchWrapper.ps1 is the main file you are after.  

Launch Minecraft Server.bat is simply a batch file that you can point to with a shortcut file to launch the script. Then a shortcut files can be placed in your start menu or all-users desktop.  

I'm just a dad who wanted my 5 kids to be able to play Minecraft together without having to fight over which of their worlds they were going to join. Now they can all build in one family world no matter who is playing at that time. As such, I didn't want the server running all the time, don't have dedicated hardware for it, etc. With this set up, I have a simple icon on our family desktop that any kid can launch and everything just works.


FEATURES
--------
1) Launches the server in a manner that allows the script to send and receive commands to/from the server.
2) Prevents the PC from sleeping while the Minecraft server is running.
3) Backs up the world at configurable frequency. Unlike all other wrappers I found, this uses interactive features native to Bedrock Server that do NOT require the server to be shut down!
4) Shut down the server if no one is online for a configurable time period.
5) Automatically checks for and upgrades the server on launch. (Since this script is written for home use, expectation isn't that the server runs for days on end.)


INSTALLATION STEPS
------------------

You will need to install Bedrock Server from https://www.minecraft.net/en-us/download/server/bedrock. Subsequent runs will auto-update, but I haven't (yet) set the script up to do a clean initial install. Message me if you are interested in that. 

In the .ps1 file, you will want to edit the "Configuration Variables" near the top of the file. Then you'll want to edit the .bat file to include the proper path the the .ps1 file. Then I recommend creating a shortcut to the .bat file placed in all users desktop (I found all users desktop following instructions here: https://superuser.com/questions/984866/how-to-make-a-desktop-shortcut-available-for-all-users-in-windows-10).

### Configuration Variables
  $sleepSetting - While the Minecraft server is running, the computer will be set not to sleep. Afterwards, it will be set to sleep after this many minutes.

  $serverLocation - Directory where bedrock_server.exe lives. 

  $backupLocation - Directory to store backup files - SHOULD NOT be inside $serverLocation (or vice versa)

  $backupMinutes  - How frequently after starting to create automatic backups. Minecraft doesn't 'save', but we play in survival mode and sometimes a savepoint can restore what the 5-year-old accidentally destroyed. To restore a backup, open the $serverLocation folder, worlds subfolder, and the folder of the world you are playing ("Bedrock level" by default). Delete the entire db folder. Then paste all files in the backup zip into this location, overwriting files. 

  $maxBackups - Maximum number of backup archives before oldest one gets deleted. Frequent backups can fill the harddrive. I haven't yet made this smart enough to do an incremental scheme or monitor disk space, so it's up to you. 

  $idleShutdown - After how many minutes of no one being logged in should we stop the server? Rembember, once the server is stopped, the computer will be set to sleep again. 
