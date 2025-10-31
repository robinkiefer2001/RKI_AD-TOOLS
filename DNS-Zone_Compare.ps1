<#
.SYNOPSIS
Vergleicht lokale DNS-Zoneneinträge mit öffentlichen DNS-Auflösungen.

.DESCRIPTION
Dieses Skript lädt eine lokale DNS-Zone vom Windows DNS-Server, speichert sie als CSV-Datei, 
führt eine öffentliche DNS-Auflösung aller enthaltenen Hostnamen (A und CNAME) durch, 
und erstellt anschliessend eine Vergleichstabelle.

.AUTHOR
Robin Kiefer

.VERSION
1.0

.NOTES
- Voraussetzung: PowerShell-Ausführung auf einem System mit installiertem DNS-Server-Modul.
- Benötigt Internetzugriff auf 1.1.1.1 für öffentliche DNS-Auflösung.
#>

# ----------------------------------------
# KONFIGURATION & VARIABLE DEFINITIONS
# ----------------------------------------

# Zielordner für temporäre Dateien
$folderPath = "C:\temp"

# Abruf aller vorhandenen DNS-Zonen vom lokalen DNS-Server
$dnsZones = Get-DnsServerZone

# ----------------------------------------
# FUNKTIONEN
# ----------------------------------------

function Compare-Set {
    <#
    .SYNOPSIS
    Vergleicht zwei Arrays elementweise nach Inhalt.

    .PARAMETER a
    Erstes Array

    .PARAMETER b
    Zweites Array

    .OUTPUTS
    [bool] True, wenn beide Mengen gleich sind (unabhängig von Reihenfolge)

    #>
    param (
        [array]$a,
        [array]$b
    )

    $aClean = $a | Where-Object { $_ -and $_ -ne "" } | ForEach-Object { "$_" } | Sort-Object -Unique
    $bClean = $b | Where-Object { $_ -and $_ -ne "" } | ForEach-Object { "$_" } | Sort-Object -Unique

    if ($aClean.Count -ne $bClean.Count) { return $false }

    for ($i = 0; $i -lt $aClean.Count; $i++) {
        if ($aClean[$i] -ne $bClean[$i]) {
            return $false
        }
    }

    return $true
}

# ----------------------------------------
# ORDNER & ZONENAUSWAHL
# ----------------------------------------

# Zielordner erstellen, falls nicht vorhanden
if (-not (Test-Path $folderPath)) {
    New-Item -Path $folderPath -ItemType Directory | Out-Null
}

# Benutzer wählt Zone via GUI
$selectedZone = $dnsZones | Select-Object -ExpandProperty ZoneName | Out-GridView -Title "Wähle eine DNS-Zone" -PassThru

# Abbruch, wenn keine Auswahl getroffen
if (-not $selectedZone) {
    Write-Host "Keine Zone ausgewählt. Skript wird beendet."
    exit
}

# ----------------------------------------
# EXPORT DER LOKALEN ZONENDATEN
# ----------------------------------------

$zoneRecords = Get-DnsServerResourceRecord -ZoneName $selectedZone

# Dateiname erzeugen (zeitgestempelt + zufällig)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$random = -join ((65..90)+(97..122)+(48..57) | Get-Random -Count 5 | ForEach-Object {[char]$_})
$extension = ".csv"
$localExportName = "${selectedZone}_${timestamp}_${random}${extension}"
$exportPath = Join-Path $folderPath $localExportName

# Nur lesbare Daten extrahieren und in CSV exportieren
$zoneRecords | Select-Object `
    HostName,
    RecordType,
    RecordClass,
    TimeToLive,
    @{Name = "Data"; Expression = {
        try {
            $rd = $_.RecordData
            switch ($_.RecordType) {
                "A"     { $rd.IPv4Address.IPAddressToString }
                "AAAA"  { $rd.IPv6Address.IPAddressToString }
                "CNAME" {
                    $target = $rd.HostNameAlias
                    if ($target.EndsWith(".")) { $target = $target.Substring(0, $target.Length - 1) }
                    $target
                }
                default { $rd.ToString() }
            }
        } catch {
            "-"
        }
    }} | Export-Csv -Path $exportPath -Encoding UTF8 -NoTypeInformation

# Wieder einlesen für Vergleich
$zoneFile_Records = Import-Csv -Path $exportPath

# ----------------------------------------
# ÖFFENTLICHE DNS-AUFLÖSUNG
# ----------------------------------------

$results = @()

foreach ($record in $zoneRecords) {
    $HostName = $record.HostName
    if (-not $HostName.ToLower().EndsWith($selectedZone.ToLower())) {
        $HostName = "$HostName.$selectedZone"
    }

    $isCname = ($record.Type -eq 5)
    $targetName = $null
    $errorMessage = $null
    $resolvable = $false

    if ($isCname) {
        $targetName = $record.RecordData.HostNameAlias.TrimEnd(".")
        try {
            $resultCNAME = Resolve-DnsName -Name $targetName -Server "1.1.1.1" -ErrorAction Stop
            $resolvable = $true
        } catch {
            $errorMessage = "CNAME-Ziel '$targetName' nicht auflösbar: $($_.Exception.Message)"
        }
    }

    try {
        $resultA = Resolve-DnsName -Name $HostName -Server "1.1.1.1" -ErrorAction Stop
        $hostResolvable = $true
    } catch {
        $hostResolvable = $false
        $errorMessage = "Record '$HostName' nicht auflösbar: $($_.Exception.Message)"
    }

    $results += [PSCustomObject]@{
        HostName           = $HostName
        Type               = $record.RecordType
        TargetName         = if ($isCname) { @($targetName, $resultCNAME.NameHost) | Where-Object { $_ } | Sort-Object -Unique } else { @($resultA.IPAddress) }
        PubliclyResolvable = if ($isCname) { $resolvable } else { $hostResolvable }
        Error              = $errorMessage
    }
}

# Export der öffentlichen Auflösung
$publicExportName = "${selectedZone}_publicDNS_${timestamp}_${random}${extension}"
$publicExportPath = Join-Path $folderPath $publicExportName
$results | Export-Csv -Path $publicExportPath -NoTypeInformation -Encoding UTF8

$publicRecordsFile = Import-Csv -Path $publicExportPath

# ----------------------------------------
# VERGLEICHSDATEN ERSTELLEN
# ----------------------------------------

$vergleich = @()

# Alle vorkommenden Hostnamen zusammenfassen
$alleHostnames = @(
    $zoneFile_Records | ForEach-Object {
        $name = $_.HostName
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $selectedZone }
        elseif (-not $name.ToLower().EndsWith($selectedZone.ToLower())) { $name = "$name.$selectedZone" }
        $name.ToLower()
    }
    $results | ForEach-Object { $_.HostName.ToLower() }
) | Sort-Object -Unique

foreach ($hostname in $alleHostnames) {

    # Lokale Daten finden
    $local = $zoneFile_Records | Where-Object {
        $hn = $_.HostName
        if ([string]::IsNullOrWhiteSpace($hn)) { $hn = $selectedZone }
        elseif (-not $hn.ToLower().EndsWith(".$($selectedZone.ToLower())")) { $hn = "$hn.$selectedZone" }
        $hn.ToLower() -eq $hostname
    }

    # Öffentliche Daten finden
    $public = $results | Where-Object {
        $_.HostName -and $_.HostName.ToLower() -eq $hostname
    }

    # Vorhanden
    $lokalVorhanden = if ($local) { "Ja" } else { "Nein" }
    $publicVorhanden = if ($public) { "Ja" } else { "Nein" }

    # Rohdaten extrahieren
    $localDataRaw = if ($local) { $local | ForEach-Object { $_.Data } } else { @("-") }
    $publicDataRaw = if ($public) { $public | ForEach-Object { $_.TargetName } } else { @("-") }

    # Bereinigen
    $localDataClean = ($localDataRaw | Where-Object { $_ -and $_ -ne "" } | Sort-Object -Unique)
    $publicDataClean = ($publicDataRaw | Where-Object { $_ -and $_ -ne "" } | Sort-Object -Unique)

    # Vergleich durchführen
    $werteGleich = if (
        $localDataClean -and $publicDataClean -and (Compare-Set $localDataClean $publicDataClean)
    ) { "Ja" } else { "Nein" }

    # Typ festlegen
    $type = if ($local) {
        ($local | ForEach-Object { $_.RecordType } | Sort-Object -Unique) -join ", "
    } elseif ($public) {
        ($public | ForEach-Object { $_.Type } | Sort-Object -Unique) -join ", "
    } else {
        "Unbekannt"
    }

    # Vergleichszeile bauen
    $vergleich += [PSCustomObject]@{
        HostName             = $hostname
        Type                 = $type
        LokalVorhanden       = $lokalVorhanden
        OeffentlichVorhanden = $publicVorhanden
        WerteGleich          = $werteGleich
        LokaleData           = $localDataClean
        OeffentlicheData     = $publicDataClean
    }
}

# ----------------------------------------
# AUSGABE
# ----------------------------------------

$vergleich | Format-Table -AutoSize

# ----------------------------------------
# EXPORT AUF DEN DESKTOP & TEMPORÄRE DATEIEN LÖSCHEN
# ----------------------------------------

# Desktop-Pfad ermitteln
$desktopPath = [Environment]::GetFolderPath("Desktop")

# Finaler CSV-Dateiname für Benutzer
$finalFileName = "DNS_Vergleich_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss")
$finalExportPath = Join-Path $desktopPath $finalFileName

# Export auf Desktop
$vergleich | Export-Csv -Path $finalExportPath -Encoding UTF8 -NoTypeInformation

Write-Host "`nVergleich gespeichert unter:`n$finalExportPath" -ForegroundColor Green

# Temporäre Dateien löschen
try {
    Get-ChildItem -Path $folderPath -Filter "*.csv" | Remove-Item -Force
    Write-Host "Temporäre CSV-Dateien im Ordner $folderPath wurden gelöscht." -ForegroundColor Yellow
} catch {
    Write-Warning "Fehler beim Löschen der temporären Dateien: $_"
}
