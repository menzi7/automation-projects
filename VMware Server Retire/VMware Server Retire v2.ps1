#Requires -RunAsAdministrator

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope Session -Confirm:$False | Out-Null
Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false | Out-Null

New-EventLog -Source "MM" -LogName Application -Erroraction SilentlyContinue

Write-Host "`r`nVMware Server Retire`r`n" -ForegroundColor Cyan

$domain1Connections = @(
    'ch-pvv-vcsa01.comp-host.com',
    'gf-pvv-vcsa01.domain1.local',
    'gf-pvv-vcsa02.domain1.local',
    'sc-pvv-vcsa01.domain1.local',
    'sc-pvv-vcsa02.domain1.local',
    'uit-pvv-vcsa01.domain1.local'
)
$domain2Connections = @(
    's2-pvv-vcsa01.domain2.local',
    'uit2-pvv-vcsa01.domain2.local',
    'uit2-pvv-mvcsa01.domain2.local',
    'syn-pvv-vcsa01.domain2.local',
    'ftl-pvv-vcsa01.domain2.local'
)

function Initialize-Retire {
    $domain1ConnectionSuccess = Open-vCenterConnections -credentials $domain1Credential -connections $domain1Connections
    $domain2ConnectionSuccess = Open-vCenterConnections -credentials $domain2Credential -connections $domain2Connections

    if (!$domain1ConnectionSuccess) {
        Write-Host "Connection failed with domain1.local credentials"
        $global:domain1Credential = $null
        $domain1Credential = Get-CredentialsWithRetry -credentialName "domain1.local"
        Initialize-Retire
    }
    if (!$domain2ConnectionSuccess) {
        Write-Host "Connection failed with domain2.local credentials"
        $global:domain2Credential = $null
        $domain2Credential = Get-CredentialsWithRetry -credentialName "domain2.local"
        Initialize-Retire
    }
    if ($domain1ConnectionSuccess -and $domain2ConnectionSuccess) {
        Write-Host "`r`nConnected to:" -ForegroundColor Green
        $global:DefaultVIServers.Name
        Write-Host
        Get-VMwareServer
    }
}

function Get-CredentialsWithRetry {
    param (
        [string]$credentialName
    )
    switch ($credentialName) {
        "domain1.local" { $hint = "xxx.admin" }
        "domain2.local" { $hint = "admXXX" }
    }
    $attempts = 0
    $credential = $null
    while (!$credential -and $attempts -lt 3) {
        $credential = Get-Credential -Message "Enter your $credentialName credentials (to connect to vCenters)`r`n$hint"
        if (!$credential) {
            $attempts++
            Write-Host "Invalid $credentialName credentials. Attempt $attempts of 3."
        }
    }
    if (!$credential) {
        Write-Host "Failed to get valid $credentialName credentials after 3 attempts. Exiting.`r`n"
        Exit
    }
    return $credential
}

function Open-vCenterConnections {
    param (
        [PSCredential]$credentials,
        [array]$connections
    )
    Foreach ($connection in $connections) {
        try {
            Connect-ViServer -Server $connection -Credential $credentials -ErrorAction Stop | Out-Null
        } catch {
            # Check if the error is related to invalid credentials
            if ($_.Exception -match "incorrect user name or password") {
                Write-Host "Authentication failed for $($connection): Incorrect username or password." -ForegroundColor Yellow
                Return $false
            } else {
                Write-Host "Critical error connecting to $($connection):" -ForegroundColor Red
                Write-Host "$($_.Exception.Message)" -ForegroundColor Red
                Exit 1
            }
        }
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
        Write-Host "No VMs found with the name $($ServerName)"
        WhatNow
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
    if ($Result.Count -eq 0) {
        Write-Host "No VMs found with the name $($ServerName)"
        WhatNow
    } else {
        Confirm-VM
    }
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
            Write-Host "Exiting the selection process." -ForegroundColor Red
            WhatNow
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
                WhatNow
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
                WhatNow
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

    if ($myVM.PowerState -eq "PoweredOn" -and $Null -ne $FQDN) {
        #Create MM event if VM is PoweredOn and has FQDN
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
            Write-Host "`r`nCreated Maintenance Mode event for $FQDN"
            Write-Host "Wait 90 seconds to ensure the server is in Maintenace Mode"
        }
        catch {
            Write-Host "`r`nFailed to create scom MM event." -ForegroundColor Red
            Break
        }

        $Seconds = 90
        $Message = "Wait 90 seconds to ensure the server is in Maintenace Mode..."
        ForEach ($Count in (1..$Seconds)) {
            # Update the progress
            Write-Progress -Id 1 -Activity $Message -Status "Waiting for $Seconds seconds, $($Seconds - $Count) left" -PercentComplete (($Count / $Seconds) * 100)
            # Check if 's' key is pressed
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true).Key
                if ($key -eq 'S') {
                    $stop = $true
                    break
                }
            }
            # Sleep for a second
            Start-Sleep -Seconds 1
        }

        if ($stop) {
            Write-Host "`r`nMM countdown skipped by user." -ForegroundColor Yellow
            Write-Host "`r`nProceeding with retire`r`n" -ForegroundColor Cyan
        } else {
            Write-Host "$FQDN is now in Maintenance Mode" -ForegroundColor Green
            Write-Host "`r`nProceeding with retire`r`n" -ForegroundColor Cyan
        }
    }
    if ($myVM.PowerState -eq "PoweredOn") {
        Write-Host "Please wait $myVM is shutting down."
        try {
            Get-VM "$myVM" | Shutdown-VMGuest -ErrorAction Stop -Confirm:$false | Out-Null
        } catch {
            # If vm doesn not have VMware Tools
            Get-VM "$myVM" | Stop-VM -Confirm:$false | Out-Null
        }
        $limit = 10
        $counter = 0
        do {
            Start-Sleep -Seconds 5
            $myVM = Get-VM -Name "$ServerName"
            $status = $myVM.PowerState
            Write-Host "Please wait $myVM is shutting down."
            $counter++
            if ($counter -ge $limit) {
                # Force VM shutdown and restart counter
                try {
                    Write-Host "Initiating VM Force Stop"
                    Get-VM "$myVM" | Stop-VM -Confirm:$false | Out-Null
                    $counter = 0
                } catch {
                    if ($_.Exception -match "The operation is not allowed in the current state") {
                        Write-Host "Force Stop failed, VM is in shutting down state." -ForegroundColor Yellow
                        $counter = 0
                    }
                    elseif ($_.Exception -match "The attempted operation cannot be performed in the current state (Powered off)") {
                        $status = $myVM.PowerState
                        $counter = 0
                    }
                    else {
                        Write-Host "$($_.Exception.Message)" -ForegroundColor Red
                        $counter = 0
                    }
                }
            }
        }
        until($status -eq "PoweredOff")
        Write-Host "$myVM has shutdown`r`n"
        Start-Sleep -Seconds 1
    }
    else { Write-Host "`r`n$myVM is already turned off`r`n" }

    try {
        $ExclusionTag = Get-Tag -Name "Excluded" -Server "$($myVM.UID.Split('@')[1].Split(':')[0])" -ErrorAction Stop
        Get-VM -Name "$myVM" | New-TagAssignment -Tag $ExclusionTag -ErrorAction Stop -Confirm:$false | Out-Null
        Write-Host "$myVM has beem excluded from TSM VE backup."
    } catch { Write-Host "TSM VE Exclude tag doesn't exist on the vCenter. Please check if the tag is missing or if there isn't TSM VE on the vCenter." }

    $newVMname = $myVM.name + " (decom " + $ChangeID + ")"
    Get-VM -Name "$myVM" | Set-VM -Name "$newVMname" -Confirm:$false | Out-Null
    Write-Host "$myVM has been renamed to '$myVM (decom $ChangeID)'"

    Write-Host "Server retired successfully" -ForegroundColor Green

    WhatNow
}

function WhatNow {
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

if (!$domain1Credential) { $domain1Credential = Get-CredentialsWithRetry -credentialName "domain1.local" }
if (!$domain2Credential) { $domain2Credential = Get-CredentialsWithRetry -credentialName "domain2.local" }

Initialize-Retire