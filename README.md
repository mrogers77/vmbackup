# vmbackup
Disclaimer:  This project is intended to be useful but is to be used at your own risk.

This is a project using PowerShell to interface with Veeam Backup &amp; Replication FREE edition to automate all your vm backups.  This was setup to work with VMWare ESXi.  I have added a parameter -Platform to allow this to work with Hyper-V as well but I don't have the setup to verify this.


Setup Instructions:
1. Open the VMBackup.ps1 script and modify the (2) lines towards the top that say "EDIT this path" to fit your environment
2. Run the script with the -EditVars flag which will prompt you to enter information for the script to use later. (Don't mind all the errors as they should be from the script not knowing where to log the changes you are making.)
3. Run the script as many times as you need with the -AddVM flag to add your vms to the configuration file.  You can also use other flags with this to specify the days in which you want that vm backed up (-CustomDays 0,1,2,3,4,5,6) or the retention policy for it (-CustomAutoDelete).
4. Run the script with the -RemoveVM flag twice.  Once you can remove SampleVM1 and again to remove SampleVM2.

