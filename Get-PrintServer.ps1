function Get-PrintServerInventory {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ComputerName = $env:COMPUTERNAME,

        [string]$ExportCsvPath,

        [switch]$GroupByIp
    )

    Write-Verbose "Verbinde zu $ComputerName ..."
    $sessionParams = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }

    try {
        # Drucker, Ports und Treiber einmalig laden (performant)
        $printers = Get-CimInstance @sessionParams -ClassName Win32_Printer
        $ports    = Get-CimInstance @sessionParams -ClassName Win32_TCPIPPrinterPort
        $drivers  = Get-CimInstance @sessionParams -ClassName Win32_PrinterDriver
    }
    catch {
        Write-Error "Konnte nicht zu $ComputerName verbinden: $_"
        return
    }

    $results = foreach ($p in $printers) {
        # passenden TCP/IP-Port finden
        $port = $ports | Where-Object { $_.Name -eq $p.PortName } | Select-Object -First 1

        # passenden Treiber finden (gleichnamig und auf demselben Server installiert)
        $drv = $drivers | Where-Object {
            $_.Name -eq $p.DriverName -and ($_.SystemName -eq "\\$ComputerName" -or [string]::IsNullOrEmpty($_.SystemName))
        } | Select-Object -First 1

        # Heuristik fuer V3/V4: V4 nutzt i.d.R. PrintConfig.dll als ConfigFile/DependentFile
        $isV4 = $false
        if ($drv) {
            $dep = @()
            if ($drv.DependentFiles) { $dep = $drv.DependentFiles -split '\|' }
            if ($drv.ConfigFile -match 'PrintConfig\.dll' -or ($dep -match 'PrintConfig\.dll')) { $isV4 = $true }
        }

        # Ausgabeobjekt bauen
        [PSCustomObject]@{
            ComputerName     = $ComputerName
            PrinterName      = $p.Name
            ShareName        = $p.ShareName
            Shared           = [bool]$p.Shared
            Published        = [bool]$p.Published
            DriverName       = $p.DriverName
            DriverVersion    = if ($drv) { $drv.DriverVersion } else { $null }
            DriverEnvironment= if ($drv) { $drv.SupportedPlatform } else { $null }
            DriverType       = if ($drv) { if ($isV4) { 'V4' } else { 'V3 (vermutet)' } } else { $null }
            PortName         = $p.PortName
            IPAddress        = if ($port) { $port.HostAddress } else { $null }
            PortProtocol     = if ($port) { switch ($port.Protocol) { 1{'RAW'} 2{'LPR'} default { $port.Protocol } } } else { $null }
            PortNumber       = if ($port) { $port.PortNumber } else { $null }
            SNMPEnabled      = if ($port) { [bool]$port.SNMPEnabled } else { $null }
            QueueStatus      = $p.PrinterStatus         # numerisch, aber nuetzlich fuer Rohanalyse
            WorkOffline      = [bool]$p.WorkOffline
            Comment          = $p.Comment
            Location         = $p.Location
        }
    }

    if ($GroupByIp) {
        $grouped = $results | Group-Object IPAddress | ForEach-Object {
            [PSCustomObject]@{
                IPAddress        = $_.Name
                Queues           = ($_.Group | Select-Object -ExpandProperty PrinterName) -join ', '
                ShareNames       = ($_.Group | Where-Object Shared | Select-Object -ExpandProperty ShareName) -join ', '
                Drivers          = ($_.Group | Select-Object -ExpandProperty DriverName -Unique) -join ' | '
                DriverTypes      = ($_.Group | Select-Object -ExpandProperty DriverType -Unique) -join ' | '
                CountQueues      = $_.Count
            }
        }

        if ($ExportCsvPath) {
            $grouped | Sort-Object IPAddress | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $ExportCsvPath
            Write-Host "Gruppierte Auswertung exportiert nach: $ExportCsvPath"
        }
        return $grouped | Sort-Object IPAddress
    }
    else {
        if ($ExportCsvPath) {
            $results | Sort-Object IPAddress, PrinterName | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $ExportCsvPath
            Write-Host "Inventar exportiert nach: $ExportCsvPath"
        }
        return $results | Sort-Object IPAddress, PrinterName
    }
}

# Beispiele:
# Alle Drucker lokal anzeigen
# Get-PrintServerInventory
0
# Remote Printserver abfragen und CSV exportieren
# Get-PrintServerInventory -ComputerName PRINTSRV01 -ExportCsvPath 'C:\Temp\printserver_inventar.csv'

# Gruppierte Sicht: Welche Queues haengen an derselben IP?
# Get-PrintServerInventory -ComputerName PRINTSRV01 -GroupByIp
