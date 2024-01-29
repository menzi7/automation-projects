#Requires -RunAsAdministrator

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope Session -Confirm:$False | Out-Null
Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false | Out-Null

Write-Host "`r`nVMware Server Retire`r`n" -ForegroundColor Cyan

$vCenterConnections = @(
    'pvv-vcsa.mst.local'
)

function Get-CredentialsWithRetry {
    $attempts = 0
    $credential = $null
    while (!$credential -and $attempts -lt 3) {
        $credential = Get-Credential -Message "Enter your credentials (to connect to vCenters)"
        if (!$credential) {
            $attempts++
            Write-Host "Invalid credentials. Attempt $attempts of 3."
        }
    }
    if (!$credential) {
        Write-Host "Failed to get valid credentials after 3 attempts. Exiting.`r`n"
        return $null
    }
    return $vCenterCredential
}

function Initialize-Retire {
    $vCenterConnectionSuccess = Open-vCenterConnections -credentials $vCenterCredential -connections $vCenterConnections

    if (!$vCenterConnectionSuccess) {
        Write-Host "Connection failed with service.outforce.dk credentials"
        $vCenterCredential = $null
        Return
    }
    if ($vCenterConnectionSuccess) {
        Write-Host "`r`nConnected to:" -ForegroundColor Green
        $global:DefaultVIServers.Name
        Write-Host
        Get-VMwareServer
    }
}

function Open-vCenterConnections {
    param (
        [PSCredential]$credentials,
        [array]$connections
    )
    Foreach ($connection in $connections) {
        try {
            Connect-ViServer -Server $connection -Credential $credentials -ErrorAction Stop | Out-Null
        } catch { Return $false }
    }
    Return $true
}

function Get-VMwareServer {
    $ServerName = Read-Host "Enter servername - NOT FQDN"
    Write-Host

    try {
        $VMs = Get-VM -Name "*$ServerName*" -ErrorAction Stop
    }
    catch {
        Write-Host "Server with name '$ServerName' was not found... Stopped"
        return
    }

    $Result = @()
    foreach ($vm in $VMs) {
        $VMHost = Get-VMHost | Where-Object { $_.Name -eq $vm.VMHost.Name }
        if ($VMHost) {
            $entry = [PSCustomObject]@{
                VM      = $vm
                vCenter = $VMHost.UID.Split('@')[1].Split(':')[0]
                FQDN    = $vm.Guest.Hostname
            }
            $Result += $entry
        }
    }
    $Result | Select-Object VM, FQDN, vCenter
    Confirm-VM
}

function Confirm-VM {
    $ConfirmedVM = $null
    if ($Result.Count -ge "2") {
        # More than one server found
        # Display a numbered list of entries in columns
        $formatString = "{0,-2} {1,-20} {2,-35} {3,-35}"
        Write-Host ($formatString -f "", "VM", "FQDN", "vCenter")

        for ($i = 0; $i -lt $Result.Count; $i++) {
            Write-Host ($formatString -f ($i + 1), $Result[$i].VM, $Result[$i].FQDN, $Result[$i].vCenter)
        }

        # Prompt the user to select an entry
        $selectedEntryIndex = Read-Host "`r`nSelect the VM by entering the corresponding number (q to quit)"

        # Check if the user entered 'q' to quit
        if ($selectedEntryIndex -eq "q") {
            Write-Host "Exiting the selection process."
            Return
        }
        # Check if the user's input is a valid number
        elseif ($selectedEntryIndex -match '^\d+$' -and [int]$selectedEntryIndex -ge 1 -and [int]$selectedEntryIndex -le $Result.Count) {
            # User entered a valid number
            $selectedEntry = $Result[$selectedEntryIndex - 1]
        }
        else {
            Write-Host "Invalid selection. Please enter a valid number.`r`n" -ForegroundColor Red
            Confirm-VM
        }

        if ($Null -ne $selectedEntry.FQDN) {
            # The FQDN exists
            $ConfirmedVM = $selectedEntry
        }
        else {
            # The FQDN doesn't exist
            $ConfirmedVM = $selectedEntry
        }
    }
    else {
        # Only one VM found
        if ($null -ne $Result.FQDN) {
            # The FQDN exists
            $Confirmation = $(Write-Host "Found: " -NoNewline) + $(Write-Host "$($Result.FQDN)" -ForegroundColor Cyan -NoNewline) + $(Write-Host " on: " -NoNewline) + $(Write-Host "$($Result.vCenter)" -ForegroundColor Cyan -NoNewline) +
            $(Write-Host " - Is this the right server? y/n " -NoNewline; Read-Host)
            if ($Confirmation -eq 'y') {
                Write-Host "Confirmed`r`n" -ForegroundColor Green

                $ConfirmedVM = $Result
            }
            else {
                Write-Host "Stopped" -ForegroundColor Red
                Break
            }
        }
        else {
            # The FQDN doesn't exist
            $Confirmation = $(Write-Host "Found: " -NoNewline) + $(Write-Host "$($Result.VM)" -ForegroundColor Cyan -NoNewline) + $(Write-Host " on: " -NoNewline) + $(Write-Host "$($Result.vCenter)" -ForegroundColor Cyan -NoNewline) +
            $(Write-Host " - Is this the right server? y/n " -NoNewline; Read-Host)
            if ($Confirmation -eq 'y') {
                Write-Host "Confirmed`r`n" -ForegroundColor Green

                $ConfirmedVM = $Result
            }
            else {
                Write-Host "Stopped" -ForegroundColor Red
                Break
            }
        }
    }
    Suspend-VM
}

function Suspend-VM {
    $FQDN = $null
    if ($Null -ne $ConfirmedVM.FQDN) {
        # $ConfirmedVM has FQDN
        $myVM = (Get-VM | Where-Object { $_.Guest.HostName -eq "$($ConfirmedVM.FQDN)" })

        $FQDN = $myVM.Guest.Hostname

        $(Write-Host "`r`nVM: " -NoNewline) + $(Write-Host "$($FQDN)" -ForegroundColor Cyan -NoNewline) + $(Write-Host " on: " -NoNewline) + $(Write-Host "$($myVM.UID.Split('@')[1].Split(':')[0])" -ForegroundColor Cyan -NoNewline)
    }
    else {
        # $ConfirmedVM does not have FQDN
        $myVM = Get-VM -Name "$($ConfirmedVM.VM)"

        $(Write-Host "`r`nVM: " -NoNewline) + $(Write-Host "$($myVM.Name)" -ForegroundColor Cyan -NoNewline) + $(Write-Host " on: " -NoNewline) + $(Write-Host "$($myVM.UID.Split('@')[1].Split(':')[0])" -ForegroundColor Cyan -NoNewline)
    }

    $ChangeID = Read-Host "`r`nEnter change-id"

    # Maintenance mode event here

    if ($myVM.PowerState -eq "PoweredOn") {
        Write-Host "Please wait $myVM is shutting down."
        try {
            Get-VM "$myVM" | Shutdown-VMGuest  -Confirm:$false | Out-Null
        } catch {
            # If vm doesn not have VMware Tools
            Get-VM "$myVM" | Stop-VM -Confirm:$false | Out-Null
        }
        $limit = 8
        $counter = 0
        do {
            Start-Sleep -Seconds 5
            $myVM = Get-VM -Name "$ServerName"
            $status = $myVM.PowerState
            Write-Host "Please wait $myVM is shutting down."
            $counter++
            if ($counter -ge $limit) {
                # Force VM shutdown and restart counter
                Get-VM "$myVM" | Stop-VM -Confirm:$false | Out-Null
                $counter = 0
            }
        }
        until($status -eq "PoweredOff")
        Write-Host "$myVM has shutdown`r`n"
        Start-Sleep -Seconds 1
    }
    else { Write-Host "`r`n$myVM is already turned off`r`n" }

    Get-VM -Name "$myVM" | Set-VM -Name "$myVM (decom $ChangeID)" -Confirm:$false | Out-Null
    Write-Host "$myVM has been renamed to '$myVM (decom $ChangeID)'"

    Write-Host "Server retired successfully" -ForegroundColor Green

    Write-Host "`r`nWhat now?" -ForegroundColor Cyan
    Write-Host " 1: Retire another server"
    Write-Host " 2: Exit"
    $WhatNow = Read-Host
    if ($WhatNow -eq 1) {
        Write-Host "`r`n`r`n"
        Get-VMwareServer
    }
    else {
        Break
    }
}

if (!$vCenterCredential) { $vCenterCredential = Get-CredentialsWithRetry }

Initialize-Retire
