#Requires -RunAsAdministrator

Clear-Host

Write-Host "`r`nDelete server in AD and remove DNS records`r`n" -ForegroundColor Cyan

function Remove-ADServer {

    # Turns textinput into variable
    $myServer = Read-Host "Enter the name of the server you want to delete. NOT FQDN"
    $myDNSServer = "localhost"

    # checking wether or not textboxes are empty
    if ([string]::IsNullOrEmpty($myServer)) {
        Write-Host "Servername can't be empty... Stopped" -ForegroundColor Red
        return
    }

    # Import Active Directory Module
    Import-Module ActiveDirectory

    # Delete the server in AD
    try {
        Get-ADComputer -Identity $myServer -Server $myDNSServer | Remove-ADObject -Recursive -Confirm:$True -ErrorAction Stop
        Write-Host "'$myServer' has been deleted in AD"
    }
    catch {
        Write-Host "Server with name '$myServer' was not found in AD`r`nObject could be protected from deletion or permission denied" -ForegroundColor Red
    }

    # Remove dns records
    $aRecord = $null
    $ptr = $null

    try {
        $AZones = Get-DnsServerZone -ComputerName $myDNSServer |
        Where-Object { $_.IsReverseLookupZone -eq $false }
    }
    catch {
        Write-Host "Failed to enumerate forward zones from the server." -ForegroundColor Red
    }

    try {
        $PTRZones = Get-DnsServerZone -ComputerName $myDNSServer |
        Where-Object { $_.IsReverseLookupZone -eq $true }
    }
    catch {
        Write-Host "Failed to enumerate reverse zones from the server." -ForegroundColor Red
    }

    foreach ($fwdZone in $AZones) {
        if ($aRecord = Get-DnsServerResourceRecord -ComputerName $myDNSServer -ZoneName $fwdZone.ZoneName -RRType A | 
            Where-Object { $_.HostName -like "*$($myServer)*" }) {
            try {
                Remove-DnsServerResourceRecord -InputObject $aRecord -ZoneName $fwdZone.ZoneName -ComputerName $myDNSServer -Force -Confirm:$false
                $(Write-Host "Successfully removed forward record for " -NoNewline) + $(Write-Host "$($myServer)" -ForegroundColor Cyan -NoNewline) + $(Write-Host " from " -NoNewline) + $(Write-Host "$($fwdZone.ZoneName)" -ForegroundColor Cyan)
            }
            catch {
                Write-Host "Something vent wrong, please check for A records manually" -ForegroundColor Red
            }
        }
    }

    foreach ($zone in $PTRZones) {
        if ($ptr = Get-DnsServerResourceRecord -ComputerName $myDNSServer -ZoneName $zone.ZoneName -RRType Ptr | 
            Where-Object { $_.RecordData.PtrDomainName -like "*$($myServer)*" }) {
            try {
                Remove-DnsServerResourceRecord -InputObject $ptr -ZoneName $zone.ZoneName -ComputerName $myDNSServer -Force -Confirm:$false
                $(Write-Host "Successfully removed PTR record for " -NoNewline) + $(Write-Host "$($myServer)" -ForegroundColor Cyan -NoNewline) + $(Write-Host " from " -NoNewline) + $(Write-Host "$($zone.ZoneName)" -ForegroundColor Cyan)
            }
            catch {
                Write-Host "Something vent wrong, please check for PTR records manually" -ForegroundColor Red
            }
        }
    }

    Write-Host "Script completed" -ForegroundColor Green

    Write-Host "`r`nWhat now?" -ForegroundColor Cyan
    Write-Host " 1: Delete another server"
    Write-Host " 2: Exit"
    $WhatNow = Read-Host
    if ($WhatNow -eq 1) {
        Clear-Host
        Remove-ADServer
    }
    else {
        Exit
    }

}

Remove-ADServer
