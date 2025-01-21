# Get Spooler service object
$PrintSpooler = Get-Service -Name Spooler

#Restart Printer Spooler Service on WorkStation
Restart-Service $PrintSpooler

Write-Host $PrintSpooler.DisplayName "restarted"
