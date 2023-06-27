#Requires -RunAsAdministrator

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope Session -Confirm:$False 
Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false | Out-Null

New-EventLog -Source "MM" -LogName Application -Erroraction SilentlyContinue

Clear-Host

Write-Host "`r`nVMware Server Retire`r`n" -ForegroundColor Cyan

If (-not $Credential) { 
    Write-Host "Enter your vcenter credentials (to connect to vCenters)`r`n"
    $Credential = Get-Credential -Message "Enter your vcenter credentials (to connect to vCenters)" 
}

$Connections = @(
    'vcenter01',
    'vcenter02',
    'vcenter03'
)

Foreach ($Connection in $Connections) {
    try {
        Connect-ViServer -Server $Connection -Credential $Credential -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "Invalid credentials... Stopped" -ForegroundColor Red
        $Credential = $Null
        Exit
    }
}

function Suspend-VMwareServer {

    Write-Host "`rConnected to:" -ForegroundColor Green
    $global:DefaultVIServers.Name
    Write-Host

    $ServerName = Read-Host "Enter servername - NOT FQDN"
    $ChangeID = Read-Host "Enter change-id"
    Write-Host

    try {
        $myVM = Get-VM -Name "$ServerName" -ErrorAction Stop
    }
    catch {
        Write-Host "Server with name '$ServerName' was not found... Stopped"
        Exit
    }

    $FQDN = (Get-VM "$ServerName").Guest.Hostname

    if ($Null -eq $FQDN) {
        $Confirmation = $(Write-Host "Found: " -NoNewline) + $(Write-Host "$myVM" -ForegroundColor Cyan -NoNewline) + $(Write-Host " - Is this the right server? y/n " -NoNewline; Read-Host)
        if ($Confirmation -eq 'y') {
            Write-Host "Confirmed`r`n" -ForegroundColor Green
        }
        else {
            Write-Host "Stopped" -ForegroundColor Red
            Exit
        }
    }
    else {
        $Confirmation = $(Write-Host "Found: " -NoNewline) + $(Write-Host "$FQDN" -ForegroundColor Cyan -NoNewline) + $(Write-Host " - Is this the right server? y/n " -NoNewline; Read-Host)
        if ($Confirmation -eq 'y') {
            Write-Host "Confirmed`r`n" -ForegroundColor Green
        }
        else {
            Write-Host "Stopped" -ForegroundColor Red
            Exit
        }

        $MMParams = @{
            LogName   = 'Application'
            Source    = 'MM'
            EntryType = 'Information'
            EventID   = 201
            Category  = 0
            Message   = "$($FQDN) 99999 $($ChangeID)"
        }
        try {
            Write-EventLog @MMParams -ErrorAction Stop
            Write-Host "Putting $FQDN into Maintenance Mode"
            Write-Host "Wait 90 seconds to ensure the server is in Maintenace Mode"
        }
        catch {
            Write-Host "Failed to create scom MM event." -ForegroundColor Red
            Exit
        }
    
        [int]$Time = 90
        $Lenght = $Time / 100
        For ($Time; $Time -gt 0; $Time--) {
            $min = [int](([string]($Time / 60)).split('.')[0])
            $text = " " + $min + " minutes " + ($Time % 60) + " seconds left"
            Write-Progress -Activity "Watiting for..." -Status $Text -PercentComplete ($Time / $Lenght)
            Start-Sleep 1
        }
    
        Write-Host "$FQDN is now in Maintenace Mode" -ForegroundColor Green
    
    }

    Write-Host "`r`nProceeding with retire`r`n" -ForegroundColor Cyan

    $myVMTags = Get-TagAssignment "$myVM"

    if ($myVM.PowerState -eq "PoweredOn") {
        Write-Host "Please wait $myVM is shutting down."
        Get-VM "$myVM" | Shutdown-VMGuest  -Confirm:$false | Out-Null
        do {
            Start-Sleep -Seconds 5
            $myVM = Get-VM -Name "$ServerName"
            $status = $myVM.PowerState
            Write-Host "Please wait $myVM is shutting down."
        }
        until($status -eq "PoweredOff")
        Write-Host "$myVM has shutdown`r`n"
        Start-Sleep -Seconds 1
    }
    else { Write-Host "$myVM is already turned off`r`n" }

    Remove-TagAssignment $myVMTags -Confirm:$false
    Write-Host "Removed tags from $myVM"

    $DecomTags = Get-Tag -Name "DECOM_NOSPLA"
    foreach ($DecomTag in $DecomTags) {
        try {
            Get-VM -Name "$myVM" | New-TagAssignment -Tag $DecomTag -Confirm:$false | Out-Null
        }
        catch {}
    }
    Write-Host "Assigned decom tag to $myVM"

    Get-VM -Name "$myVM" | Set-VM -Name "$myVM (decom $ChangeID)" -Confirm:$false | Out-Null
    Write-Host "$myVM has been renamed to '$myVM (decom $ChangeID)'"

    Write-Host "Server retired successfully" -ForegroundColor Green

    Write-Host "`r`nWhat now?" -ForegroundColor Cyan
    Write-Host " 1: Retire another server"
    Write-Host " 2: Exit"
    $WhatNow = Read-Host
    if ($WhatNow -eq 1) {
        Clear-Host
        Suspend-VMwareServer
    }
    else {
        Exit
    }

}

Suspend-VMwareServer

