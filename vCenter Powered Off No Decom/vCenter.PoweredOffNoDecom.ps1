<#
.SYNOPSIS
  Monthly report of powered off VMs.
.DESCRIPTION
  The PoweredOffNoDecom.ps1 script generates a list of VMs that are turned off, without a proper decom.
  It creates a ticket in topdesk with the info generated.
  The script can also generate and exprt a CSV with the same info if parameter is used.
  VDAs, CTX and CA servers are ignored.
.NOTES
  Author: TME
  Ticket: UIT2302-1753
.PARAMETER OutputPath
  Specifies the path for the CSV-based output file. By default, no file is generated.
.EXAMPLE
  PS> .\PoweredOffNoDecom.ps1
.EXAMPLE
  PS> .\PoweredOffNoDecom.ps1 -OutputPath "C:\Reports\2023-02\PoweredOffVM.csv"
#>

#Requires -Modules xxx.HelperFunctions, xxx.Thycotic, xxx.TopDesk, xxx.TOTP, CredentialManager, ImportExcel

param (
  [string]$OutputPath
)

$Credential = Get-TssCredentialObject -secretId 2970

$Connections = @(
    'vcenter01',
    'vcenter02',
    'vcenter03'
)

Foreach ($Connection in $Connections) {
  Connect-ViServer -Server $Connection -Credential $Credential
}

$Report = [PSCustomObject]@()
$VMs = ""

$ExcludeTag = Get-Tag -Name "DECOM_NOSPLA"
$VMs = (Get-VM).Where{ $_.PowerState -eq 'Poweredoff' -and $_.Name -notlike "*VDA*" -and $_.Name -notlike "*CTX*" -and $_.Name -notlike "*VW-CA*" -and $_.Name -notlike "*VW-ROOTCA*" -and $_.Name -notlike "*beholdes*" }
$Tags = $VMs | Get-TagAssignment
$VMHost = Get-VMHost | Select-Object Name, @{N = "vCenter"; E = { $_.UID.Split('@')[1].Split(':')[0] } }

$PowerOffEvents = Get-VIEvent -Entity $VMs -MaxSamples ([int]::MaxValue) | Where-Object { $_ -is [VMware.Vim.VmPoweredOffEvent] } | Group-Object -Property { $_.Vm.Name }

ForEach ($VM in $VMs) {

  # Assinged tag
  $Tags | Where-Object { $_.Entity.Name -eq $VM.Name } | 
  ForEach-Object -Process {
    $ATag = $_.Tag.Name
  }

  # Get vCenter
  $VMHost | Where-Object { $_.Name -eq $VM.VMHost.name } |
  ForEach-Object -Process {
    $vCenter = $_.vCenter
  }

  # Skip VM if it is properly decom
  if ($ExcludeTag.Name -contains $ATag -and $VM.Name -like "*decom*") { continue }

  $lastPO = ($PowerOffEvents | Where-Object { $_.Group[0].Vm.Vm -eq $VM.Id }).Group | Sort-Object -Property CreatedTime -Descending | Select-Object -First 1
  $row = "" | Select-Object VMName, Cluster, vCenter, Tags, PoweredOffTime, PoweredOffBy
    $row.VMName = $VM.Name
    $row.Cluster = $VM.VMHost.Parent.Name
    $row.vCenter = $vCenter
    $row.Tags = $ATag
    $row.PoweredOffTime = $lastPO.CreatedTime
    $row.PoweredOffBy = $lastPO.UserName
  $report += $row

}

# Output to CSV.
if ($OutputPath) {
  $report | Sort-Object vCenter, Tags, VMName | Export-Csv -Path $OutputPath -NoTypeInformation -UseCulture
}

$briefDescription = "Slukkede VMs uden decom"
$ticketBody = "`r<b>Slukkede VMs uden decom</b>`r 
Download nedenstående mail for listen `r `n
Undersøg om serveren er decommet, og der er glemt navn/tag - eller om kunden selv har slukket den uden at informere os? `r 
Hvis serveren har et change/ticket nummer i navnet, undersøg hvorfor den er slukket. Følg gerne op på om den fortsat skal beholdes. `r `n
Kontakt kunden og spørg, hvad der skal ske med serveren. Vil de beholde den? Skal den decommes?`r
Hvis serveren skal beholdes, tilføj <i>(beholdes [ticket nummer])</i> til servernavnet i VMware. fx. <i>PRODDOK (beholdes UIT2010-9999)</i>"

$Ticket = New-TopDeskOperationsTicket -briefDescription $briefDescription -ticketBody $ticketBody 
Write-host 'TopDesk ticket [' + $Ticket.number + '] created ' -ForegroundColor Green

$Sreport = $report | Sort-Object vCenter, Tags, VMName
$VMTable = ConvertTo-HtmlTable -InputObject $Sreport
$EmailSubject = "$($Ticket.number) - $($briefDescription)"
$EmailBody = New-HtmlEmailBody -subject $briefDescription -Summary $VMTable

Send-EmailMessage -To support@unit-it.dk -Subject $EmailSubject -Body $EmailBody
Write-host 'Email with subject [' $EmailSubject '] sent' -ForegroundColor Green