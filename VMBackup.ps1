<#

.SYNOPSIS
This script was created to automate backups of virtual machines on ESXI hosts

.DESCRIPTION
This script initializes Veeam Backup and Replication after getting the required parameters from a configuration file.

.EXAMPLE
.\VMBackup.ps1

.EXAMPLE
.\VMBackup.ps1 -config <\\Path\To\Config\File>

.EXAMPLE
.\VMBackup.ps1 -vm "SampleVM" -destination "\\<server>\<driveletter>$\SampleVM\" -Compression 5 -AutoDelete "In1Week" -DisableQuiesce

.EXAMPLE
.\VMBackup.ps1 -AddVM

.PARAMETER Compression
According to Veeam:
Specifies the integer number corresponding to the desired compression level:

0 - None. Consider disabling compression to achieve better deduplication ratios on deduplicating storage
    appliances at the cost of reduced backup performance.
	
4 - Dedupe-friendly. This is the recommended setting for using with deduplicating storage devices and caching
    WAN accelerators. This setting is used by default.
	
5 - Optimal (recommended). Optimal compression provides for the best compression to performance ratio, and
    lowest backup proxy CPU usage.
	
6 - High compression level provides additional 10% compression ratio over the Optimal level at the cost of
    about 10x higher CPU usage.

9 - Extreme. Extreme compression provides additional 3% compression ratio over High, at the cost of 2x higher
    CPU usage.

.PARAMETER AutoDelete
Specifies the retention settings for the VeeamZip file:

Never
Tonight
TomorrowNight
In3days
In1Week
In2Weeks
In1Month

.PARAMETER DisableQuiesce
Using this switch will cause VeeamZip to not use VMWare Tools Quiescence

.PARAMETER EditConfig
This switch will enable you to modify the current configuration file without having to edit the xml

.PARAMETER AddVM
This switch will allow you to add a vm to the configuration file using default values

.PARAMETER ListVMs
Use this switch to list the vms you already have in your configuration file 

.PARAMETER RemoveVM
This switch will allow you to remove a vm from the configuration file.  All settings for that vm will be lost

.PARAMETER MonthlyArchive
Using this parameter on the first day of the month will copy the most recent VBK files from the <vmname> folders in your srvRoot directory into a MonthlyArchive folder in your srvRoot directory

.PARAMETER CustomDays
This will allow you to specify which days you want to back up a vm while adding it to the configuration file

.PARAMETER VmBackupReportHeader
This sets a custom header message on the notification email

.PARAMETER ListConfig
This switch will list the configuration file contents

.PARAMETER EditVars
This switch will let you change the configuration file variables such as email info, and log paths

.PARAMETER CustomAutoDelete
If you use this parameter when adding a vm to your configuration file you will be prompted to enter how long you want to retain your backups.  You will get one prompt for each day you selected to perform a backup.

.PARAMETER Platform
This option can be used to specify if you are backing up a vm running on VMware or Hyper-V platform.  This defaults to VMware.

.NOTES
Version: 1.4
Author:	  Micah Rogers
Created:  August 2016
Configuration file should be in xml format

Prerequisites:
Must have Veeam Backup and Replication installed on the computer or server you are running the script on to perform the backup.  Tested on version 9.0
PowerShell 3.0

Instructions:
Specify the srvRoot directory in the configuration file.
Create a folder called "Backup" in the srvRoot folder
Put the PowerShell script and configuration file in the Backup folder
Search this script for "EDIT this path" to find the lines you will need to modify for your use.  Everything else should be stored in the configuration file.

#>


########################################
### Setup switch functions
########################################

param(
	[ValidateScript({Test-Path $_})][string]$configFile = "\\MyServer1\<driveletter>$\Backup\VMBackup_Default_Config.xml"    <# EDIT this path #>,
	[Parameter(ValueFromPipeline)][string]$vm,
	[string]$destination = "\\MyServer1\<driveletter>$\$vm",  <# EDIT this path #>
	[ValidateSet(0,4,5,6,9)][int]$Compression = 5,
	[ValidateSet("Never","Tonight","TomorrowNight","In3days","In1Week","In2Weeks","In1Month")][string]$AutoDelete = "In1Week",
	[Alias("DQ")][Switch]$DisableQuiesce,
	[Switch]$EditConfig,
	[Switch]$AddVM,
	[Switch]$RemoveVM,
	[Switch]$ListVMs,
	[Switch]$MonthlyArchive,
	[ValidateSet(0,1,2,3,4,5,6)][array]$CustomDays = @(0,1,2,3,4,5,6),
	[string]$VmBackupReportHeader = ("VM backup results for " + (Get-Date -Format yyyy-MM-dd)),
	[Switch]$ListConfig,
	[Switch]$EditVars,
	[Alias("CAD")][Switch]$CustomAutoDelete,
	[ValidateSet("HyperV","Hyper-V","VMware")][string]$Platform = "VMware"
)

Function writeToLog ($msg) {
	$timestamp = Get-Date -Format yyyy-MM-dd-hh:mm:ss
	Add-Content $logFile "$timestamp   $msg"
}

#Set variables not dependant on configuration file
$jobTS = Get-Date -Format yyyy-MM-dd-hhmmss
$timestamp = Get-Date -Format yyyy-MM-dd-hh:mm:ss
$date = Get-Date -Format yyyy-MM-dd
$CustDays = ,$CustomDays

#Determine Day and which command variables to run
$dayOfWeek = (Get-Date).dayOfWeek.value__
$dayOfWeek = "$dayOfWeek"
$dayOfMonth = (Get-Date).day

function setVars() {
#Set other variables
	$Script:srvRoot = $config.vars.srvRoot
	$Script:logPath = $config.vars.logPath
	$Script:logFile = $logPath + $jobTS + ".log"
	$Script:logFile2 = $logPath + $jobTS + "_email.log"
	$Script:veeamLogPath = $config.vars.veeamLogPath
	$Script:emailTo = $config.vars.emailTo
	$Script:mailServer = $config.vars.mailServer
	$Script:emailFrom = $config.vars.emailFrom
	$Script:emailSubject = $config.vars.emailSubject
}

if (!(Test-Path "$srvRoot\Backup\Logs")) {
	New-Item "$srvRoot\Backup\Logs" -ItemType Directory
}

if (!(Test-Path "$srvRoot\Backup\Logs")) {
	Write-Host "Backup folder needs created and this script should be placed in that folder" -ForegroundColor "red"
	sleep 7
	exit
}

#Get list of VMs and parameters
$config = Import-Clixml $configFile
setVars
if ($vm) {
	writeToLog("Getting backup parameters from command line")
} else {
	writeToLog("Getting backup parameters from $configFile")
}

function listVMs() {
	$config.vms | foreach {write-host ("`n" + $_.vm) -ForegroundColor "yellow"}
}

if ($ListVMs) {
	listVMs
	Remove-Item $logFile
	exit
}

function listConfig() {
	$config.vms | foreach {
		write-host ("`n" + $_.vm) -ForegroundColor "yellow"
		if ($_."0".shouldBackup -eq $true) {write-host "  0  - Sunday    " -ForegroundColor "Cyan";  $_."0" }
		if ($_."1".shouldBackup -eq $true) {write-host "  1  - Monday    " -ForegroundColor "Cyan";  $_."1" }
		if ($_."2".shouldBackup -eq $true) {write-host "  2  - Tuesday   " -ForegroundColor "Cyan";  $_."2" }
		if ($_."3".shouldBackup -eq $true) {write-host "  3  - Wednesday " -ForegroundColor "Cyan";  $_."3" }
		if ($_."4".shouldBackup -eq $true) {write-host "  4  - Thursday  " -ForegroundColor "Cyan";  $_."4" }
		if ($_."5".shouldBackup -eq $true) {write-host "  5  - Friday    " -ForegroundColor "Cyan";  $_."5" }
		if ($_."6".shouldBackup -eq $true) {write-host "  6  - Saturday  " -ForegroundColor "Cyan";  $_."6" }
	}
	write-host ("`n`nOther Variables:") -ForegroundColor "yellow"
	$config.vars
}

if ($ListConfig) {
	listConfig
	Remove-Item $logFile
	exit
}

#This feature in progress to make it easier to edit the configuration file.  Current functionality is limited to adding and removing vms with mostly default options.
if ($EditConfig -or $AddVM -or $RemoveVM -or $EditVars) {
	Copy-Item $configFile ($configFile + ".bak")
	listVMs
	writeToLog("Modifying configuration file")
	if (!($vm) -and ($AddVM -or $RemoveVM)) {$vm = Read-Host "Please Enter VM Name"}  ###check if $vm is null
	
	#Determine variables for which days to backup and for other settings to use
	if ($CustDays -match 0) {
		$backupSun = $true
		if ($CustomAutoDelete) {
			write-host "Options Include:`n","Never","Tonight","TomorrowNight","In3days","In1Week","In2Weeks","In1Month"
			if (($cADSun = Read-Host "How long would you like to retain Sunday's backup [In1Week]") -eq '') {$custAutoDelSun = "In1Week"} else {$custAutoDelSun = $cADSun} 
		} else {
			$custAutoDelSun = "In1Week"
		}
	} else {
		$backupSun = $false
	}
	if ($CustDays -match 1) {
		$backupMon = $true
		if ($CustomAutoDelete) {
			write-host "Options Include:`n","Never","Tonight","TomorrowNight","In3days","In1Week","In2Weeks","In1Month"
			if (($cADMon = Read-Host "How long would you like to retain Monday's backup [In1Week]") -eq '') {$custAutoDelMon = "In1Week"} else {$custAutoDelMon = $cADMon} 
		} else {
			$custAutoDelMon = "In1Week"
		}
	} else {
		$backupMon = $false
	}
	if ($CustDays -match 2) {
		$backupTue = $true
		if ($CustomAutoDelete) {
			write-host "Options Include:`n","Never","Tonight","TomorrowNight","In3days","In1Week","In2Weeks","In1Month"
			if (($cADTue = Read-Host "How long would you like to retain Tuesday's backup [In1Week]") -eq '') {$custAutoDelTue = "In1Week"} else {$custAutoDelTue = $cADTue} 
		} else {
			$custAutoDelMon = "In1Week"
		}
	} else {
		$backupTue = $false
	}
	if ($CustDays -match 3) {
		$backupWed = $true
		if ($CustomAutoDelete) {
			write-host "Options Include:`n","Never","Tonight","TomorrowNight","In3days","In1Week","In2Weeks","In1Month"
			if (($cADWed = Read-Host "How long would you like to retain Wednesday's backup [In1Week]") -eq '') {$custAutoDelWed = "In1Week"} else {$custAutoDelWed = $cADWed} 
		} else {
			$custAutoDelMon = "In1Week"
		}
	} else {
		$backupWed = $false
	}
	if ($CustDays -match 4) {
		$backupThu = $true
		if ($CustomAutoDelete) {
			write-host "Options Include:`n","Never","Tonight","TomorrowNight","In3days","In1Week","In2Weeks","In1Month"
			if (($cADThu = Read-Host "How long would you like to retain Thursday's backup [In1Week]") -eq '') {$custAutoDelThu = "In1Week"} else {$custAutoDelThu = $cADThu}
		} else {
			$custAutoDelMon = "In1Week"
		} 
	} else {
		$backupThu = $false
	}
	if ($CustDays -match 5) {
		$backupFri = $true
		if ($CustomAutoDelete) {
			write-host "Options Include:`n","Never","Tonight","TomorrowNight","In3days","In1Week","In2Weeks","In1Month"
			if (($cADFri = Read-Host "How long would you like to retain Friday's backup [In1Week]") -eq '') {$custAutoDelFri = "In1Week"} else {$custAutoDelFri = $cADFri}  
		} else {
			$custAutoDelMon = "In1Week"
		}
	} else {
		$backupFri = $false
	}
	if ($CustDays -match 6) {
		$backupSat = $true
		if ($CustomAutoDelete) {
			write-host "Options Include:`n","Never","Tonight","TomorrowNight","In3days","In1Week","In2Weeks","In1Month"
			if (($cADSat = Read-Host "How long would you like to retain Saturday's backup [In1Week]") -eq '') {$custAutoDelSat = "In1Week"} else {$custAutoDelSat = $cADSat} 
		} else {
			$custAutoDelMon = "In1Week"
		}
	} else {
		$backupSat = $false
	}
	
	# Remove VM from Config
	if ($RemoveVM) {
		[System.Collections.ArrayList]$config.vms = $config.vms | where {$_.vm -notmatch $vm}
		writeToLog("Removed $vm")
	}
	
	# Add VM to config
	if ($AddVM) {
		$config.vms.Add(@{
			"vm" = $vm;
			"0" = @{ "shouldBackup" = $backupSun; "autoDelete" = "In1Week"; "compression" = 5; "destination" = "$srvRoot\$vm\"; "DisableQuiesce" = $false};
			"1" = @{ "shouldBackup" = $backupMon; "autoDelete" = "In1Week"; "compression" = 5; "destination" = "$srvRoot\$vm\"; "DisableQuiesce" = $false};
			"2" = @{ "shouldBackup" = $backupTue; "autoDelete" = "In1Week"; "compression" = 5; "destination" = "$srvRoot\$vm\"; "DisableQuiesce" = $false};
			"3" = @{ "shouldBackup" = $backupWed; "autoDelete" = "In1Week"; "compression" = 5; "destination" = "$srvRoot\$vm\"; "DisableQuiesce" = $false};
			"4" = @{ "shouldBackup" = $backupThu; "autoDelete" = "In1Week"; "compression" = 5; "destination" = "$srvRoot\$vm\"; "DisableQuiesce" = $false};
			"5" = @{ "shouldBackup" = $backupFri; "autoDelete" = "In1Week"; "compression" = 5; "destination" = "$srvRoot\$vm\"; "DisableQuiesce" = $false};
			"6" = @{ "shouldBackup" = $backupSat; "autoDelete" = "In1Week"; "compression" = 5; "destination" = "$srvRoot\$vm\"; "DisableQuiesce" = $false};
		})
		writeToLog("Added $vm")
	}
	
	if ($EditVars) {
		#Edit EmailFrom Variable
		if (!($emailFromNew = Read-Host "Enter email address to send from [$emailFrom]") -eq '') {writeToLog("Changed sender email from $emailFrom to $emailFromNew"); $emailFrom = $emailFromNew}
		$config.vars.Remove("emailFrom")
		$config.vars.Add("emailFrom",$emailFrom)
		
		#Edit logPath Variable		
		if (!($logPathNew = Read-Host "Enter log path [$logPath]") -eq '') {writeToLog("Changed log path from $logPath to $logPathNew"); $logPath = $logPathNew}
		$config.vars.Remove("logPath")
		$config.vars.Add("logPath",$logPath)
		
		#Edit emailTo Variable		
		if (!($emailToNew = Read-Host "Enter email address to send to [$emailTo]") -eq '') {writeToLog("Changed email recipient from $emailTo to $emailToNew"); $emailTo = $emailToNew}
		$config.vars.Remove("emailTo")
		$config.vars.Add("emailTo",$emailTo)
		
		#Edit emailSubject Variable		
		if (!($emailSubjectNew = Read-Host "Enter subject for email report [$emailSubject]") -eq '') {writeToLog("Changed email subject from $emailSubject to $emailSubjectNew"); $emailSubject = $emailSubjectNew}
		$config.vars.Remove("emailSubject")
		$config.vars.Add("emailSubject",$emailSubject)
		
		#Edit veeamLogPath Variable		
		if (!($veeamLogPathNew = Read-Host "Enter Veeam log path [$veeamLogPath]") -eq '') {writeToLog("Changed Veeam log path from $veeamLogPath to $veeamLogPathNew"); $veeamLogPath = $veeamLogPathNew}
		$config.vars.Remove("veeamLogPath")
		$config.vars.Add("veeamLogPath",$veeamLogPath)
		
		#Edit srvRoot Variable		
		if (!($srvRootNew = Read-Host "Enter server drive root or base folder for vm backups [$srvRoot]") -eq '') {writeToLog("Changed server root directory from $srvRoot to $srvRootNew"); $srvRoot = $srvRootNew}
		$config.vars.Remove("srvRoot")
		$config.vars.Add("srvRoot",$srvRoot)
		
		#Edit mailServer Variable		
		if (!($mailServerNew = Read-Host "Enter your mail server name [$mailServer]") -eq '') {writeToLog("Changed mail server from $mailServer to $mailServerNew"); $mailServer = $mailServerNew}
		$config.vars.Remove("mailServer")
		$config.vars.Add("mailServer",$mailServer)
	}
	
	writeToLog("Applying changes")
	$config | Export-Clixml $configFile
	writeToLog("Finished modifying configuration file")
	
	exit
}

#Add to log that the script was called and started successfully
writeToLog("Starting VM backup process")

(Add-Content $logFile2 "<h3>$VmBackupReportHeader :</h3>  <br>")

Function addToEmail ($emsg) {
	Add-Content $logFile2 "$emsg"
}

if($dayOfMonth -eq 1){
	writeToLog("Cleaning up past log file archives")
	Remove-Item $logPath*.zip
	writeToLog("Compressing recent logfiles")
	Compress-Archive (Get-ChildItem $logPath* | sort LastWriteTime -Desc | select -Skip 2) $logPath"OldLogs.zip"
	writeToLog("Removing uncompressed recent logfiles")
	Get-ChildItem $logPath* | sort LastWriteTime -Desc | select -Skip 3 | Remove-Item
}

Function logReporting {
	if ($veeamLogStatus -eq "Success") {
		writeToLog("$vm backup completed with Success")
		Add-Content $logFile2 ("<tr><td width='10%'><a href=$destination>$vm</a></td> <td width='10%'>$veeamLogStatus</td><td width='80%'></td></tr>")
	} 
	if ($veeamLogStatus -eq "Warning") {
		writeToLog("$vm backup completed with a Warning")
		addToEmail("<tr><td width='10%'><a href=$destination>$vm</a></td> <td width='10%'><a href=$veeamLog>$veeamLogStatus</a></td><td width='80%'></td></tr>")
	}
	if ($veeamLogStatus -eq "Failed") {
		writeToLog("$vm backup FAILED!")
		Add-Content $logFile2 ("<tr><td width='10%'><a href=$destination>$vm</a></td> <td width='10%'><a href=$veeamLog>$veeamLogStatus</a></td><td width='80%'></td></tr>")
	}
	if ($installVMwareTools -eq "Need Installed") {
		writeToLog("Please make sure VMware Tools are installed on $vm")
	}
	if ($veeamLogStatus -eq $null) {
		$veeamLogFolder = (Get-ChildItem $veeamLogPath\$vm* | sort LastWriteTime -Descending | where {$_ -match $vm} | select -First 1 | foreach {$_.Name})
		$veeamLogFolder = $veeamLogPath + $veeamLogFolder + "\"
		if (Test-Path ($veeamLogFolder + (Get-ChildItem $veeamLogFolder | select Name | where {$_ -match "Task"} | foreach {$_.Name}))) {
			$Script:veeamLog = ($veeamLogFolder + (Get-ChildItem $veeamLogFolder | select Name | where {$_ -match "Task"} | foreach {$_.Name}))
		} else {
			$Script:veeamLog = $logFile
		}
		$veeamLogStatus = "Failed"
		#If VeeamLog is older than 8 hours then don't use it
		writeToLog("$vm was unable to complete.  The Veeam services may have been terminated.")
		addToEmail("<tr><td width='10%'><a href=$destination>$vm</a></td> <td width='10%'><a href=$veeamLog>Failed</a></td><td width='80%'></td></tr>")
	}
}

Function getVeeamLogStatus {
	$veeamLogFolder = $job.LogsSubFolder
	$veeamLogFolder = $veeamLogPath + $veeamLogFolder + "\"
	$Script:veeamLog = ($veeamLogFolder + (Get-ChildItem $veeamLogFolder | select Name | where {$_ -match "Task"} | foreach {$_.Name}))
	$veeamLogFCont = Get-Content $veeamLog
	if ($veeamLogFCont -match "Cannot use VMware Tools quiescence because VMware Tools are not found.") {
		$Script:installVMwareTools = "Need Installed"
	}
}

#Load Veeam Toolkit - This assumes a default installation of Veeam Backup and Replication on the C:\ drive.  If you are using a custom installation, you may need to modify the path to the "Initialize-VeeamToolkit.ps1" script
writeToLog("Loading VeeamToolkit")
& "C:\Program Files\Veeam\Backup and Replication\Backup\Initialize-VeeamToolkit.ps1"

#Initiate backup process
#Create table for email
addToEmail("<table border='0' cellpadding='0' cellspacing='0' width='100%'>")
if ($vm) {
	$veeamLogCont = $null
	$veeamLogStatus = $null
	$job = $null
	if ($DisableQuiesce -eq $true) {$usingQuiesce = $false} else {$usingQuiesce = $true}
	
	writeToLog("Starting backup of $vm")
	writeToLog("-Saving backup to $destination")
	writeToLog("-Using compression level of $Compression")
	writeToLog("-Using VMWare Tools Quiescence = $usingQuiesce")
	writeToLog("-Set to auto delete $AutoDelete")
	
	#Validate any parameters
	if ($Platform -like "Hyper*") {
		$vmentity = Find-VBRHvEntity -Name $vm
	} 
	if ($Platform -like "VMware*") {
		$vmentity = Find-VBRViEntity -Name $vm
	}
	if ($vmentity -eq $null) {
	  Write-Host "VM: $vm not found" -ForegroundColor "red"
	  writeToLog("VM: $vm not found")
	  $veeamLogStatus = "Failed"
	}
	if ($DisableQuiesce -eq $true) {
		$job = Start-VBRZip -Entity $vmentity -Folder $destination -Compression $Compression -AutoDelete $Autodelete -DisableQuiesce
	} else {
		$job = Start-VBRZip -Entity $vmentity -Folder $destination -Compression $Compression -AutoDelete $Autodelete
	}
	
	sleep 10
	$veeamLogStatus = $job.Result
	if ($veeamLogStatus -eq "Warning" -or $veeamLogStatus -eq "Failed") {getVeeamLogStatus}
	logReporting

} else {
	$config.vms | foreach { 
		if ($_.$dayOfWeek.shouldBackup) {
			$vm = $_.vm
			$Compression = $_.$dayOfWeek.compression
			$DisableQuiesce = $_.$dayOfWeek.DisableQuiesce
			$destination = $_.$dayOfWeek.destination
			$AutoDelete = $_.$dayOfWeek.autoDelete
			
			$veeamLogCont = $null
			$veeamLogStatus = $null
			$job = $null
			if ($DisableQuiesce -eq $true) {$usingQuiesce = $false} else {$usingQuiesce = $true}
			
			writeToLog("Starting backup of $vm")
			writeToLog("-Saving backup to $destination")
			writeToLog("-Using compression level of $Compression")
			writeToLog("-Using VMWare Tools Quiescence = $usingQuiesce")
			writeToLog("-Set to auto delete $AutoDelete")
			
			#Validate any parameters
			if ($Platform -like "Hyper*") {
				$vmentity = Find-VBRHvEntity -Name $vm
			} 
			if ($Platform -like "VMware*") {
				$vmentity = Find-VBRViEntity -Name $vm
			}
			if ($vmentity -eq $null) {
			  Write-Host "VM: $vm not found" -ForegroundColor "red"
			  writeToLog("VM: $vm not found")
			  $veeamLogStatus = "Failed"
			}
			if ($DisableQuiesce -eq $true) {
				$job = Start-VBRZip -Entity $vmentity -Folder $destination -Compression $Compression -AutoDelete $Autodelete -DisableQuiesce
			} else {
				$job = Start-VBRZip -Entity $vmentity -Folder $destination -Compression $Compression -AutoDelete $Autodelete
			}
			
			sleep 10
			$veeamLogStatus = $job.Result
			if ($veeamLogStatus -eq "Warning" -or $veeamLogStatus -eq "Failed") {getVeeamLogStatus}
			logReporting
		}
	}
}
#Close the email table
addToEmail("</table>")

#Add footer to email file
Add-Content $logFile2 "<br><br> `n <table border='10px 0 0 0' cellpadding='0' cellspacing='0' width='100%'><tr><td width='10%'><a href=$logFile>Log file</a></td></tr></table>"

#Send email and/or write to log to confirm script ran successfully
writeToLog("The backup job has completed.")
$emailBody = (Get-Content $logFile2 | out-string )
Send-MailMessage -To $emailTo -Body $emailBody -Subject $emailSubject -bodyAsHtml -from $emailFrom -smtpServer $mailServer

#Cleanup
Remove-Item ($logPath + "*") -include *_email.log

#Refresh monthly backup if it is the first of the month
if ($MonthlyArchive) {
	if($dayOfMonth -eq 1) {
		writeToLog("Deleting previous monthly backups")
		#Delete monthly backups
		Remove-Item $srvRoot\MonthlyArchive\*             <# EDIT this path if you change default backup file location and want to use the MonthlyArchive feature #>
		writeToLog("Copying new monthly backups")
		#Copy new monthly backup from most recent backup
		Get-ChildItem $srvRoot\* | where {$_.Name -ne "Backup" -and $_.Name -ne "MonthlyArchive" -and $_.Name -ne "VBRCatalog"} | foreach { gci $_ | sort LastWriteTime -Descending | select -First 1 } | foreach {Copy-Item $_.FullName -Destination $srvRoot\MonthlyArchive }
	}
}


 <#
 History:
 1.0 : Created script to accomplish backups of virtual machines using Veeam Backup and Replication VeeamZIP (Created for FREE edition)
 1.1 : Added functionality to use a -config switch to specify an alternate configuration file or use -vm switch to specify a single VM with specific parameters or using default parameters
 1.2 : Added functionality to use -AddVM or -RemoveVM to add or remove a vm in the configuration file.  Also added -ListVMs to just show a list of vms already in your configuration file
 1.3 : Added functionality to use -CustomDays when adding a vm to your config file.  Added -VmBackupReportHeader to set a custom header on email notification.  Added -ListConfig to show a list of vms and their settings as well as the other variables in the configuration file.  Added -EditVars to modify the email info and log paths in the configuration file.  Various other improvements.
 1.4 : Added functionality to use -CustomAutoDelete when adding a vm to your configuration file.  Also added the ability to specify if you want to backup a vm on VMware or Hyper-V using -Platform <platform>
  
#> 





