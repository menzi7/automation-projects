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