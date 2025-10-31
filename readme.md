# PowerShell Skriptübersicht

Dieses Repository enthält eine Sammlung von PowerShell-Skripten, die typische Administrationsaufgaben im Active Directory, DNS- und Fileserver-Umfeld automatisieren. Ziel ist eine nachvollziehbare Dokumentation der Funktionsweise, Einsatzszenarien und Abhängigkeiten.

---

## `DNS-Zone_Compare.ps1`

**Vergleich lokaler DNS-Zoneneinträge mit öffentlichen DNS-Auflösungen**

### Funktion:

* Exportiert alle Resource Records (A, AAAA, CNAME, etc.) einer gewählten DNS-Zone vom lokalen DNS-Server
* Führt für jeden Hostnamen eine öffentliche DNS-Auflösung via `1.1.1.1` durch
* Erstellt eine tabellarische Vergleichsausgabe (lokal vs. öffentlich)
* Exportiert finale CSV auf Desktop und löscht temporäre Daten

### Voraussetzungen:

* Windows DNS-Server Modul installiert
* Internetverbindung (für `Resolve-DnsName` gegen 1.1.1.1)

### Einsatz:

Für Audits, Public Exposure Analysen oder Migrationsvorbereitungen von DNS-Zonen.

#### Link
[DNS-Zone_Compare.ps1](DNS-Zone_Compare.ps1)

---

## `dynamic_group.ps1`

**Benutzer aller (auch verschachtelter) AD-Gruppenmitglieder ermitteln und in Zielgruppe übertragen**

### Funktion:

* Ruft alle Benutzer rekursiv aus definierten Quellgruppen ab
* Eliminiert Duplikate
* Fügt Benutzer in eine Zielgruppe ein
* Validiert am Ende, ob alle Mitglieder korrekt übernommen wurden

### Verwendung:

* Als Scheduled Task einsetzbar zur Pflege dynamischer Gruppen basierend auf Organisationsstrukturen

### Voraussetzungen:

* AD-Modul für PowerShell
* Ausführung mit ausreichenden Rechten zur Gruppenmodifikation
  
#### Link
[dynamic_group.ps1](dynamic_group.ps1)

---

## `userHomeUpdate.ps1`

**Automatisiertes Anlegen von Userhome-Verzeichnissen inkl. Share und NTFS-ACLs**

### Funktion:

* Liest Benutzer aus definierter OU
* Prüft auf vorhandene Userhomes im Fileshare
* Erstellt fehlende Ordner + Share + ACL (inkl. SYSTEM, Benutzer, Adminkonto)
* Kann periodisch als Scheduled Task verwendet werden

### Konfigurierbare Parameter:

* Domain Controller
* Ziel-OU
* UNC- & lokaler Pfad
* Share-Präfix
* Admin-Account für Zusatzrechte

### Einsatz:

* Standardisierung von Benutzerordnerbereitstellung
* Automatisierter Lifecycle nach Benutzeranlage

#### Link
[userHomeUpdate.ps1](userHomeUpdate.ps1)

---

## `Get-Userhomes.ps1`

**Listet Home-Verzeichnisse aller AD-Benutzer auf**

### Funktion:

* Liest alle Benutzerattribute `homeDirectory` aus
* Gibt Zuordnung `SamAccountName -> HomeDirectory` aus

### Einsatz:

* Schneller Überblick über konfigurierten Benutzerpfade
* Kontrolle vor Migration oder Userhome-Anlage

#### Link
[Get-Userhomes.ps1](Get-Userhomes.ps1)

---

## `Read-Share-Permissions.ps1`

**Liest alle Freigaben inkl. NTFS-Berechtigungen eines Servers aus**

### Funktion:

* Ermittelt alle `Win32_Share` Einträge
* Liest zugehörige ACLs mit `Get-Acl`
* Exportiert Ergebnis als CSV auf Desktop

### Einsatz:

* Inventarisierung von Freigaben
* Berechtigungsüberprüfung vor Servermigrationen

#### Link
[Read-Share-Permissions.ps1](Read-Share-Permissions.ps1)

---

## `Sharepoint-Upload.ps1`

**Uploads ganzer Ordnerstrukturen nach SharePoint Online**

### Funktion:

* Fragt URL der Zielseite und Pfade ab
* Nutzt `PnP.PowerShell` für Verbindung und Upload
* Repliziert lokale Ordnerstruktur inklusive aller Dateien

### Voraussetzungen:

* `PnP.PowerShell` Modul installiert und importiert
* Interaktive Anmeldung mit WebLogin erforderlich

### Einsatz:

* Massenuploads in SharePoint-Dokumentenbibliotheken
* Strukturierter Datenimport aus Fileshares

#### Link
[Sharepoint-Upload.ps1](Sharepoint-Upload.ps1)

---

## `share_access_migration.ps1`

**Ermittlung von Share-Zugriffsrechten inklusive NTFS- und AD-Gruppenauflösung**

### Funktion:

* Fragt per WMI und PowerShell-Remoting (`CimSession`, `PSSession`) alle SMB-Shares eines angegebenen Fileservers ab
* Liest die Share-Berechtigungen sowie NTFS-ACLs
* Löst Benutzer und Gruppenmitglieder über AD auf, inkl. Prüfung auf gelöschte SIDs
* Stellt bereinigte Objektstruktur bereit (Share -> Benutzerrechte)

### Besonderheiten:

* Berücksichtigt Sprachunterschiede (DE/EN) für Standardgruppen wie "Administratoren"
* Nutzt eigene PowerShell-Klassen zur Objektstrukturierung (`UserObj`, `ShareObj`)

### Voraussetzungen:

* Remotezugriff per PowerShell erlaubt (WinRM)
* AD-Modul installiert für Benutzer- und Gruppenauswertung

### Einsatz:

* Dokumentation von Share-Zugriffsrechten
* Vorbereitung von Fileserver-Migrationen oder Repermissioning-Projekten

#### Link
[share_access_migration.ps1](share_access_migration.ps1)

---

## `Generate-SelfSignedRootAndSignedCert.ps1`

Dieses Skript erstellt ein selbstsigniertes Root-Zertifikat (CA) und ein durch dieses signiertes Server-Zertifikat. Es verwendet dabei automatisch den aktuellen Rechnernamen und die Domäne zur Namensbildung. Die erzeugten Zertifikate werden in die entsprechenden Zertifikatsspeicher importiert und zusätzlich exportiert.

### Funktionen

* Erstellt ein Root-Zertifikat mit den KeyUsages `CertSign` und `CRLSign`
* Importiert das Root-Zertifikat in den Zertifikatsspeicher `LocalMachine\Root`
* Generiert ein durch das Root-Zertifikat signiertes Server-Zertifikat
* Exportiert Zertifikate im `.cer`- und `.pfx`-Format in das Verzeichnis `C:\Source\Cert`
* Kopiert Zertifikatsdateien zusätzlich auf den Desktop des ausführenden Systems
* Optional: Erzeugt ein zweites Server-Zertifikat für einen weiteren Domänencontroller (DC2) und importiert es remote
* Optional: Kopiert das Server-Zertifikat in den SystemCertificates Store für NTDS

### Dateien

| Datei                                          | Beschreibung                                                              |
| ---------------------------------------------- | ------------------------------------------------------------------------- |
| `Generate-SelfSignedRootAndSignedCert.ps1`     | PowerShell-Skript zur Erstellung und Verwaltung der Zertifikate           |
| `C:\Source\Cert\PKI-[Hostname]-Root.pfx`       | Exportiertes Root-Zertifikat im PFX-Format (temporär)                     |
| `C:\Source\Cert\PKI-[Hostname]-Root.cer`       | Exportiertes Root-Zertifikat im CER-Format                                |
| `C:\Source\Cert\PKI-[Hostname]-Signed.cer`     | Exportiertes signiertes Zertifikat für DC1                                |
| `C:\Source\Cert\PKI-[Hostname]-DC2-Signed.pfx` | Optional: Exportiertes Zertifikat für DC2                                 |
| `%Desktop%\...`                                | Kopie der wichtigsten Zertifikate auf dem Desktop des aktuellen Benutzers |

### Voraussetzungen

* Ausführung als Administrator in einer PowerShell-Sitzung
* PowerShell 5.1 oder höher
* Das Verzeichnis `C:\Source\Cert` wird automatisch erstellt, falls nicht vorhanden
* Optional: DC2 muss remote erreichbar sein (WinRM aktiviert)

### Hinweise zur Verwendung

* Das Passwort für die PFX-Dateien wird beim Start des Skripts abgefragt und sollte sicher gespeichert werden, z. B. in einem Passwortmanager wie Bitwarden
* Für produktive Umgebungen wird empfohlen, echte CA-Zertifikate (z. B. von einer internen Windows-Zertifizierungsstelle oder einer offiziellen CA) zu verwenden
* Dieses Skript ist primär für Test-, Entwicklungs- oder Lab-Umgebungen gedacht

#### Link
[Generate-SelfSignedRootAndSignedCert.ps1](Generate-SelfSignedRootAndSignedCert.ps1)

---

## `Compare-SYSVOL-DFSR.ps1`

Dieses Skript vergleicht die Inhalte des SYSVOL-Verzeichnisses (`C:\Windows\SYSVOL\domain`) mehrerer Domänencontroller und prüft auf Abweichungen in der DFS-R-Replikation. Es identifiziert Unterschiede in Dateiinhalten, Zeitstempeln und Vorhandensein der Einträge auf allen angegebenen Servern.

### Funktionen

* Verbindet sich via PowerShell Remoting mit einer Liste definierter Domänencontroller
* Liest rekursiv Dateien und Ordner im SYSVOL-Verzeichnis aus
* Schließt konfliktbehaftete Einträge unter `dfsrprivate` aus
* Ermittelt:

  * Datei-/Ordner-Typ
  * SHA256-Hash für Dateien
  * Letztes Änderungsdatum (UTC)
  * Auf welchen Servern die Einträge vorhanden sind
  * Konsistenz der Inhalte (gleiche Hashes auf allen Servern)
* Gibt die Ergebnisse als Tabelle in der Konsole aus
* Exportiert die Ergebnisse als CSV-Datei auf den Desktop des aktuellen Benutzers

### Dateien

| Datei                     | Beschreibung                                                        |
| ------------------------- | ------------------------------------------------------------------- |
| `Compare-SYSVOL-DFSR.ps1` | PowerShell-Skript zur Analyse und zum Vergleich von SYSVOL-Inhalten |
| `compare_DFSR.csv`        | CSV-Ausgabe mit Vergleichsergebnissen auf dem Desktop des Benutzers |

### Voraussetzungen

* Ausführung mit administrativen Rechten
* PowerShell Remoting (WinRM) muss auf den Zielservern aktiviert sein
* PowerShell 5.1 oder höher
* Zugriff auf alle definierten Domänencontroller
* Schreibrechte auf `$HOME\Desktop` für den CSV-Export

### Hinweise zur Verwendung

* Ideal zur Fehleranalyse bei SYSVOL-Replikationsproblemen
* Unterstützt DFS-R-basierte Replikation (nicht für FRS)
* Die Liste der zu analysierenden Server wird direkt im Skript angepasst (`$servers`)

#### Link

[Compare-SYSVOL-DFSR.ps1](Compare-SYSVOL-DFSR.ps1)

---

## ``snmp-functions.ps1``

### Übersicht
Dieses PowerShell-Modul enthält zwei Funktionen zum Verwalten der **SNMP PermittedManagers** auf Windows-Servern:

- **`Get-SnmpManagers`** – Liest remote oder lokal die aktuell erlaubten SNMP-Manager aus.
- **`Add-SnmpManager`** – Fügt einen neuen SNMP-Manager hinzu und kann optional den SNMP-Dienst neu starten.

### Voraussetzungen
- Windows-Server mit installiertem SNMP-Dienst
- PowerShell Remoting / WinRM muss auf den Zielservern erreichbar sein
- Optional: Active Directory-Modul, falls Serverliste über `Get-ADComputer` bezogen wird

### Funktionen

#### `Get-SnmpManagers`
- **Parameter**
  - `-ComputerName` – Einzelner Servername oder Array. Standard: lokaler Host
- **Rückgabewerte**
  - `serverName` – Name des Servers  
  - `snmpActive` – Boolean, ob der SNMP-Dienst installiert ist  
  - `snmpManagers` – Liste der erlaubten Manager (String)  
  - `pathUsed` – Pfad, aus dem die Manager gelesen wurden (GPO oder lokal)
- **Beispiel**
```powershell
Get-SnmpManagers -ComputerName '`SRV001`', 'SRV002'

#Als Bulk
$allServers | Get-SnmpManagers
$allServers | Add-SnmpManagers -Manager xxx.xxx.xxx
```

#### Link
[snmp-functions.ps1](snmp-functions.ps1)

---

## ```Get-PrintServer.ps1```

### Übersicht
Die PowerShell-Funktion **`Get-PrintServerInventory`** ermöglicht eine vollständige Inventarisierung von Druckern auf einem lokalen oder entfernten Printserver.  
Dabei werden Druckerwarteschlangen, Ports, Treiber und weitere relevante Informationen ausgelesen. Optional kann die Ausgabe:

- **Gruppiert nach IP-Adressen** erfolgen, um zu sehen, welche Warteschlangen an derselben IP hängen.  
- **Als CSV-Datei** exportiert werden, z. B. für Reporting oder Dokumentation.

Die Funktion unterstützt sowohl lokale als auch Remote-Server über **PowerShell Remoting / WinRM**.


### Voraussetzungen
- Windows-Server oder -Client mit installierten Druckern  
- PowerShell Remoting / WinRM auf entfernten Printservern erreichbar  
- Leserechte auf Drucker, Ports und Treiber  


### Funktionsweise
1. Verbindung zum Zielserver herstellen (lokal oder remote).  
2. Auslesen von:
   - Druckern (`Win32_Printer`)  
   - TCP/IP-Ports (`Win32_TCPIPPrinterPort`)  
   - Treibern (`Win32_PrinterDriver`)  
3. Zuordnung von Druckern zu Ports und Treibern.  
4. Heuristische Erkennung von V3- vs. V4-Treibern anhand der `PrintConfig.dll`.  
5. Aufbau eines Objekts pro Drucker mit allen relevanten Eigenschaften.  
6. Optional:
   - Gruppierung nach IP-Adresse (`-GroupByIp`)  
   - Export als CSV (`-ExportCsvPath`)  


### Parameter

| Parameter          | Typ      | Beschreibung |
|-------------------|----------|-------------|
| `-ComputerName`   | string   | Zielservername. Standard: lokaler Host (`$env:COMPUTERNAME`) |
| `-ExportCsvPath`  | string   | Pfad zur CSV-Datei für Export. Wenn angegeben, wird die Ausgabe zusätzlich gespeichert |
| `-GroupByIp`      | switch   | Gruppiert Ergebnisse nach IP-Adresse der Ports und erstellt zusammengefasste Informationen pro IP |


### Rückgabewerte (pro Drucker)

| Eigenschaft          | Beschreibung |
|--------------------|-------------|
| `ComputerName`      | Name des Printservers |
| `PrinterName`       | Name der Druckerwarteschlange |
| `ShareName`         | Freigabename, falls Drucker geteilt |
| `Shared`            | Boolean, ob Drucker freigegeben ist |
| `Published`         | Boolean, ob Drucker veröffentlicht ist |
| `DriverName`        | Name des Druckertreibers |
| `DriverVersion`     | Version des Treibers |
| `DriverEnvironment` | Unterstützte Plattform(en) |
| `DriverType`        | V3 oder V4 Treiber (heuristisch) |
| `PortName`          | Name des Ports |
| `IPAddress`         | IP-Adresse des Ports (falls TCP/IP) |
| `PortProtocol`      | RAW oder LPR |
| `PortNumber`        | Portnummer |
| `SNMPEnabled`       | Boolean, ob SNMP aktiviert ist |
| `QueueStatus`       | Numerischer Status der Warteschlange |
| `WorkOffline`       | Boolean, ob offline gearbeitet wird |
| `Comment`           | Kommentar des Druckers |
| `Location`          | Standort des Druckers |

**Bei Verwendung von `-GroupByIp`** liefert die Funktion pro IP-Adresse ein Objekt mit:
- `IPAddress` – IP-Adresse der Ports  
- `Queues` – alle Warteschlangen an dieser IP  
- `ShareNames` – zusammengefasste ShareNames  
- `Drivers` – alle verwendeten Treiber  
- `DriverTypes` – Treiberversionen (V3/V4)  
- `CountQueues` – Anzahl Warteschlangen  


### Beispiele

**1. Alle Drucker lokal anzeigen**
```powershell
Get-PrintServerInventory
````

**2. Remote Printserver abfragen und CSV exportieren**

```powershell
Get-PrintServerInventory -ComputerName PRINTSRV01 -ExportCsvPath 'C:\Temp\printserver_inventar.csv'
```

**3. Gruppierte Sicht nach IP-Adressen**

```powershell
Get-PrintServerInventory -ComputerName PRINTSRV01 -GroupByIp
```

**4. Remote Server gruppiert auslesen und CSV exportieren**

```powershell
Get-PrintServerInventory -ComputerName PRINTSRV01 -GroupByIp -ExportCsvPath 'C:\Temp\printserver_ip_groups.csv'
```
### Hinweise

* Alle Drucker, Ports und Treiber werden einmalig geladen, um Performance zu verbessern.
* Gruppierte Ausgabe erleichtert die Analyse, welche Druckerwarteschlangen an derselben IP hängen.
* CSV-Export erfolgt in UTF-8 und enthält alle relevanten Informationen für Inventarisierung oder Reporting.
* Fehler bei nicht erreichbaren Servern werden gemeldet, die Funktion bricht jedoch nicht komplett ab.

Wenn du willst, kann ich jetzt noch **eine gemeinsame, ausführliche README-Sektion für beide Module (`SNMP` + `Printserver`)** erstellen, mit einheitlicher Struktur, Tabellen für Parameter/Rückgaben und Beispielen, sodass alles konsistent wirkt. Willst du, dass ich das mache?

#### Link
[Get-PrintServer.ps1](Get-PrintServer.ps1)
