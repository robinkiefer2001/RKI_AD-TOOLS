<#
.SYNOPSIS
Vergleicht SYSVOL-Inhalte mehrerer Domänencontroller zur Prüfung der DFS-R-Replikationskonsistenz.

.DESCRIPTION
Dieses Skript verbindet sich via PowerShell Remoting mit mehreren Domänencontrollern, 
liest rekursiv alle Dateien und Ordner im SYSVOL-Verzeichnis (`C:\Windows\SYSVOL\domain`) aus 
und ermittelt für jeden Eintrag:
- Vorhandensein auf den angegebenen Servern
- Dateityp (Ordner oder Datei)
- Letztes Änderungsdatum (UTC)
- SHA256-Hash (für Dateien)
- Konsistenzstatus (übereinstimmender Hash auf allen Servern)
- Server mit dem aktuellsten Stand

Die Ergebnisse werden als Tabelle ausgegeben und als CSV-Datei auf dem Desktop exportiert.

Ausschlüsse:
- DFSR-spezifische Verzeichnisse wie `dfsrprivate\conflictanddeleted` werden ignoriert.

Ziel:
Identifikation von Replikationsabweichungen zwischen SYSVOL-Replikaten.

.PARAMETER servers
Die Liste der Domänencontroller, die in den Vergleich einbezogen werden sollen.

.PARAMETER sysvolPath
Pfad zum SYSVOL-Verzeichnis, standardmäßig `C$\Windows\SYSVOL\domain`.

.OUTPUTS
Eine Tabelle in der Konsole sowie eine CSV-Datei auf dem Desktop mit folgenden Spalten:
- Path
- Type
- PresentOn
- Consistent
- MostRecentServer
- LastModified

.NOTES
Autor: Robin Kiefer  
Version: 1.0  
Letzte Änderung: 2025-07-17  
Hinweis: Ausführung benötigt administrative Rechte und aktiviertem PowerShell Remoting auf allen Zielservern.

.REQUIREMENTS
- PowerShell 5.1 oder höher
- PowerShell Remoting (WinRM) aktiviert
- Zugriff auf alle definierten Domänencontroller
- Schreibzugriff auf $HOME\Desktop

.EXAMPLE
.\Compare-SYSVOL-DFSR.ps1

Führt die Analyse mit den im Skript definierten Servern durch und exportiert das Ergebnis.
#>

# Liste der zu vergleichenden Domänencontroller
$servers = @("Dcxx", "Dcxx", "DCxx")  # DCs hier anpassen

# Pfad zur SYSVOL-Replikation
$sysvolPath = "C$\Windows\SYSVOL\domain"

# Dictionary zur Speicherung aller gefundenen Elemente (Dateien/Ordner)
$allEntries = @{}

# Durchlauf aller Server
foreach ($server in $servers) {
    Write-Host "Analysiere $server ..."
    try {
        # Aufbau einer PowerShell-Remoting-Session
        $session = New-PSSession -ComputerName $server -ErrorAction Stop

        # Abruf der Dateien und Ordner im SYSVOL-Verzeichnis
        $items = Invoke-Command -Session $session -ScriptBlock {
            $basePath = "C:\Windows\SYSVOL\domain"
            Get-ChildItem -Path $basePath -Recurse -Force | Where-Object {
                # Ausschluss des Ordners "dfsrprivate" (Konflikt-/Deleted-Daten)
                $_.FullName -notmatch "\\dfsrprivate\\"
            } | ForEach-Object {
                $full = $_.FullName
                $relative = $full.Substring($basePath.Length + 1).ToLower()
                $isFile = -not $_.PSIsContainer

                # Aufbau eines Objekts mit Datei-/Ordnerinformationen
                [PSCustomObject]@{
                    Server = $env:COMPUTERNAME
                    RelativePath = $relative
                    ItemType = if ($_.PSIsContainer) { "Folder" } else { "File" }
                    LastWriteTime = $_.LastWriteTimeUtc
                    Hash = if ($isFile) {
                        # Berechnung des SHA256-Hashes nur für Dateien
                        (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
                    } else {
                        "[DIR]"  # Platzhalter für Ordner
                    }
                }
            }
        }

        # Schließen der Remoting-Session
        Remove-PSSession -Session $session

        # Hinzufügen der gefundenen Elemente zum Haupt-Dictionary
        foreach ($item in $items) {
            if (-not $allEntries.ContainsKey($item.RelativePath)) {
                $allEntries[$item.RelativePath] = @{}
            }
            $allEntries[$item.RelativePath][$item.Server] = $item
        }

    } catch {
        Write-Warning "Verbindung zu $server fehlgeschlagen: $_"
    }
}

# Vergleichslogik
$result = foreach ($path in $allEntries.Keys) {
    $entries = $allEntries[$path]
    $hashes = $entries.Values | Select-Object -ExpandProperty Hash -Unique
    $dates = $entries.Values | Sort-Object -Property LastWriteTime -Descending

    # Erstellung eines Ergebnisobjekts mit Vergleichsinformationen
    [PSCustomObject]@{
        Path = $path
        Type = ($entries.Values | Select-Object -First 1).ItemType
        PresentOn = ($entries.Keys -join ", ")  # Auf welchen Servern vorhanden
        Consistent = ( ($hashes.Count -eq 1) -and ($entries.Count -eq $servers.Count) )  # Prüft Konsistenz
        MostRecentServer = $dates[0].Server  # Server mit aktuellster Version
        LastModified = $dates[0].LastWriteTime  # Zeitpunkt der letzten Änderung
    }
}

# Konsolenausgabe als Tabelle
$result | Format-Table Path, Type, PresentOn, Consistent, MostRecentServer, LastModified -AutoSize | Out-String -Width 200

# Export der Ergebnisse als CSV-Datei auf den Desktop
$exportPath = "$Home\Desktop\compare_DFSR.csv"
$result | Select-Object Path, Type, PresentOn, Consistent, MostRecentServer, LastModified |
    Export-Csv -Path $exportPath -Encoding UTF8 -NoTypeInformation

Write-Host "Export abgeschlossen: $exportPath"
