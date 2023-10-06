#Requires -RunAsAdministrator

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope Session -Confirm:$False | Out-Null
Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false | Out-Null

New-EventLog -Source "MM" -LogName Application -Erroraction SilentlyContinue

Write-Host "`r`nVMware Server Retire`r`n" -ForegroundColor Cyan

If (-not $domain1Credential) { 
    Write-Host "Enter your domain1 credentials (to connect to vCenters)"
    Write-Host "xxx.admin`r`n"
    $domain1Credential = Get-Credential -Message "Enter your domain1 credentials (to connect to vCenters)`r`nxxx.admin" 
}

$domain1Connections = @(
    'vcenter01.domain1',
    'vcenter02.domain1',
    'vcenter03.domain1',
    'vcenter04.domain1',
    'vcenter05.domain1',
    'vcenter06.domain1'
)

Foreach ($domain1Connection in $domain1Connections) {
    try {
        Connect-ViServer -Server $domain1Connection -Credential $domain1Credential -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "Invalid credentials... Stopped" -ForegroundColor Red
        $domain1Credential = $Null
        Exit
    }
}

If (-not $domain2Credential) { 
    Write-Host "Enter your domain2 credentials (to connect to vCenters)"
    Write-Host "admXXX`r`n"
    $domain2Credential = Get-Credential -Message "Enter your domain2 credentials (to connect to vCenters)`r`nadmXXX" 
}

$domain2Connections = @(
    'vcenter01.domain2',
    'vcenter02.domain2',
    'vcenter03.domain2',
    'vcenter04.domain2',
    'vcenter05.domain2'
)

Foreach ($domain2Connection in $domain2Connections) {
    try {
        Connect-ViServer -Server $domain2Connection -Credential $domain2Credential -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "Invalid credentials... Stopped" -ForegroundColor Red
        $domain2Credential = $Null
        Exit
    }
}

Write-Host "`rConnected to:" -ForegroundColor Green
$global:DefaultVIServers.Name
Write-Host

function Get-VMwareServer {

    $ServerName = Read-Host "Enter servername - NOT FQDN"
    $global:ChangeID = Read-Host "Enter change-id"
    Write-Host

    #Search for VMs
    $VMs = @()
    try {
        $VMs = Get-VM -Name "*$ServerName*" -ErrorAction Stop
    }
    catch {
        Write-Host "Server with name '$ServerName' was not found... Stopped"
        Exit
    }

    #Get FQDNs
    $FQDNs = @()
    foreach ($vm in $VMs) {
        $FQDNs += $vm.Guest.Hostname
    }

    #Get vCenter
    $VMHost = Get-VMHost | Select-Object Name, @{N = "vCenter"; E = { $_.UID.Split('@')[1].Split(':')[0] } }
    $vCenter = @()
    foreach ($vm in $VMs) {
        $VMHost | Where-Object { $_.Name -eq $vm.VMHost.name } |
        ForEach-Object -Process {
            $vCenter += $_.vCenter
        }
    }
    
    # Check if there are the same count of $VMs and $vCenter
    if ($VMs.Count -ne $vCenter.Count) {
        Write-Host "Arrays have different lengths. They cannot be combined."
    }
    else {
        # Initialize a new array to store the combined values
        $Result = @()

        # Loop through the arrays and combine the elements
        for ($i = 0; $i -lt $VMs.Count; $i++) {
            $entry = [PSCustomObject]@{
                VM      = $VMs[$i]
                vCenter = $vCenter[$i]
            }
            
            # Check if the index exists in $FQDN array
            if ($i -lt $FQDNs.Count) {
                $entry | Add-Member -MemberType NoteProperty -Name "FQDN" -Value $FQDNs[$i]
            }
            
            $Result += $entry
        }
        $global:Result = $Result | Select-Object VM, FQDN, vCenter
        Confirm-VM
    }
}

function Confirm-VM {
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
            Exit
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
            $(Write-Host "`r`nYou selected: " -NoNewline) + $(Write-Host "$($selectedEntry.FQDN)" -ForegroundColor Cyan -NoNewline) + $(Write-Host " on: " -NoNewline) + $(Write-Host "$($selectedEntry.vCenter)" -ForegroundColor Cyan -NoNewline)

            $global:ConfirmedVM = $selectedEntry
        }
        else {
            # The FQDN doesn't exist
            $(Write-Host "`r`nYou selected: " -NoNewline) + $(Write-Host "$($selectedEntry.VM)" -ForegroundColor Cyan -NoNewline) + $(Write-Host " on: " -NoNewline) + $(Write-Host "$($selectedEntry.vCenter)" -ForegroundColor Cyan -NoNewline)
            
            $global:ConfirmedVM = $selectedEntry
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

                $global:ConfirmedVM = $Result
            }
            else {
                Write-Host "Stopped" -ForegroundColor Red
                Exit
            }
        }
        else {
            # The FQDN doesn't exist
            $Confirmation = $(Write-Host "Found: " -NoNewline) + $(Write-Host "$($Result.VM)" -ForegroundColor Cyan -NoNewline) + $(Write-Host " on: " -NoNewline) + $(Write-Host "$($Result.vCenter)" -ForegroundColor Cyan -NoNewline) + 
            $(Write-Host " - Is this the right server? y/n " -NoNewline; Read-Host)
            if ($Confirmation -eq 'y') {
                Write-Host "Confirmed`r`n" -ForegroundColor Green

                $global:ConfirmedVM = $Result
            }
            else {
                Write-Host "Stopped" -ForegroundColor Red
                Exit
            }
        }
    }
    Suspend-VM
}

function Suspend-VM {

    if ($Null -ne $ConfirmedVM.FQDN) {
        # $ConfirmedVM has FQDN
        $myVM = (Get-VM | Where-Object { $_.Guest.HostName -match "$($ConfirmedVM.FQDN)" })

        $FQDN = (Get-VM "$myVM").Guest.Hostname

    }
    else {
        # $ConfirmedVM does not have FQDN
        $myVM = Get-VM -Name "$($ConfirmedVM.VM)"
    }

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

        Write-Host "`r`nProceeding with retire`r`n" -ForegroundColor Cyan

    }
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
    else { Write-Host "`r`n$myVM is already turned off`r`n" }

    $myVMTags = Get-TagAssignment "$myVM"

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
        Write-Host "`r`n`r`n"
        Get-VMwareServer
    }
    else {
        Exit
    }
}

Get-VMwareServer
