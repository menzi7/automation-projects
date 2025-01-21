function ConvertTo-HtmlTable {
    <#
    .SYNOPSIS
    Convert array to HTML table.
    .DESCRIPTION
    The function will convert an array to String, and return array as a HTML table.
    .PARAMETER InputObject
    When specified, the funtion converts InputObject to a HTML table.
    .EXAMPLE
    PS> ConvertTo-HtmlTable -InputObject $report
    .OUTPUTS
    System.String. ConvertTo-HtmlTable returns HTML as String.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
        [PSObject[]]$InputObject
    )

    begin {
        $header = $InputObject[0].psobject.properties.name
        $table = "<table><thead><tr>"
        foreach ($h in $header) {
            $table += "<th>$h</th>"
        }
        $table += "</tr></thead><tbody>"
    }

    process {
        foreach ($line in $InputObject) {
            $table += "<tr>"
            foreach ($h in $header) {
                $table += "<td>$($line.$h)</td>"
            } 
            $table += "</tr>"
        }
    }

    end {
        $table += "</tbody></table>"
        $table
    }
}

function Remove-DNSRecords {
    <#
    .SYNOPSIS
    Remove DNS records across all zones
    .DESCRIPTION
    This function will search for a hostname across all zones and attempt to remove them.
    Best practice is running this script directly from the DC/DNS server itself.
    .NOTES
    Author: TME
    .PARAMETER DNSserver
    Define DNS server. Remove-DNSRecords defaults to localhost. FQDN
    .PARAMETER Server
    Define the name of the server that needs to be removed from DNS. Not FQDN
    .EXAMPLE
    PS> Remove-DNSRecords -Server $ServerToDelete
    .EXAMPLE
    PS> Remove-DNSRecords -Server $ServerToDelete -DNSserver DC01.Contoso.local
    #>

    [CmdletBinding()]
    param (
        [string]$DNSserver = "localhost",
        [Parameter(Mandatory = $true)][string]$Server
    )

    $fwdRecord = $null
    $revRecord = $null

    $fwdZones = Get-DnsServerZone -ComputerName $DNSserver |
    Where-Object { $_.IsReverseLookupZone -eq $false }

    $revZones = Get-DnsServerZone -ComputerName $DNSserver |
    Where-Object { $_.IsReverseLookupZone -eq $true }

    foreach ($fwdZone in $fwdZones) {
        if ($fwdRecord = Get-DnsServerResourceRecord -ComputerName $DNSserver -ZoneName $fwdZone.ZoneName -RRType A |
            Where-Object { $_.HostName -like "*$($Server)*" }) {
            try {
                Remove-DnsServerResourceRecord -InputObject $fwdRecord -ZoneName $fwdZone.ZoneName -ComputerName $DNSserver -Force -Confirm:$false
                Write-Host "Successfully deleted A record for $($myServer) from $($fwdZone.ZoneName)"
            }
            catch {
                Write-Host "Failed to remove A record for $($myServer)" -ForegroundColor Red
            }
        }
    }

    foreach ($revZone in $revZones) {
        if ($revRecord = Get-DnsServerResourceRecord -ComputerName $DNSserver -ZoneName $revZone.ZoneName -RRType Ptr |
            Where-Object { $_.RecordData.PtrDomainName -like "*$($Server)*" }) {
            try {
                Remove-DnsServerResourceRecord -InputObject $revRecord -ZoneName $revZone.ZoneName -ComputerName $DNSserver -Force -Confirm:$false
                Write-Host "Successfully deleted PTR record for $($myServer) from $($zone.ZoneName)"
            }
            catch {
                Write-Host "Failed to remove PTR record for $($myServer)" -ForegroundColor Red
            }
        }
    }

}

function Get-HostInfo {
    <#
    .SYNOPSIS
    Gets ESXi Version, Hardware and CPU Type from hosts.
    .DESCRIPTION
    This script will get ESXi Version, Hardware and CPU Type from all hosts, that is available from currently connected vCentres.
    .NOTES
    Author: TME
    Connection to vCenter needs to be established beforehand.
    .EXAMPLE
    PS> Get-HostInfo
    #>

    get-vmhost | Select-Object Name,
    @{N = 'ESXi version'; E = { "$($_.Version) $($_.Build)" } },
    @{N = 'ESXi Hardware'; E = { "$($_.ExtensionData.Hardware.SystemInfo.Vendor) $($_.ExtensionData.Hardware.SystemInfo.Model)" } },
    @{N = 'ESXi CPU Type'; E = { $_.ProcessorType } }

}

function Search-ScheduledTasks {
    <#
    .SYNOPSIS
    Search for scheduled tasks in vCenter
    .NOTES
    Author: TME
    Connection to vCenter needs to be established beforehand.
    .EXAMPLE
    PS> Search-ScheduledTasks
    Show all scheduled tasks.
    .EXAMPLE
    PS> Search-ScheduledTasks -Keyword "UIT"
    Show all scheduled tasks with "UIT" in the name.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)][string]$Keyword
    )

    # Get all
    $ScheduledTask = (Get-View ScheduledTaskManager).ScheduledTask | % { (Get-View $_).Info }

    # Show all names and next run time
    # $ScheduledTask | Select-Object Name, NextRunTime

    # If $Keyword, search for keyword
    if ($Keyword) {
        $Tasks = ($ScheduledTask).Where{ $_.Name -like "*$($Keyword)*" }
        # Show result
        $Tasks | Select-Object Name, NextRunTime | Sort-Object Name
    }
    else {
        $ScheduledTask | Select-Object Name, NextRunTime | Sort-Object Name
    }

}

Function Start-Countdown {
    <#
    .SYNOPSIS
    Provide a graphical countdown if you need to pause a script for a period of time
    .PARAMETER Seconds
    Time, in seconds, that the function will pause
    .PARAMETER Messge
    Message you want displayed while waiting
    .EXAMPLE
    Start-Countdown -Seconds 30 -Message Please wait while Active Directory replicates data...
    .NOTES
        Author:            Martin Pugh
        Twitter:           @thesurlyadm1n
        Spiceworks:        Martin9700
        Blog:              www.thesurlyadmin.com

        Changelog:
           2.0             New release uses Write-Progress for graphical display while couting
                           down.
           1.0             Initial Release
    .LINK
    http://community.spiceworks.com/scripts/show/1712-start-countdown
    #>

    Param(
        [Int32]$Seconds = 10,
        [string]$Message = "Pausing for 10 seconds..."
    )
    ForEach ($Count in (1..$Seconds)) {
        Write-Progress -Id 1 -Activity $Message -Status "Waiting for $Seconds seconds, $($Seconds - $Count) left" -PercentComplete (($Count / $Seconds) * 100)
        Start-Sleep -Seconds 1
    }
    Write-Progress -Id 1 -Activity $Message -Status "Completed" -PercentComplete 100 -Completed
}
