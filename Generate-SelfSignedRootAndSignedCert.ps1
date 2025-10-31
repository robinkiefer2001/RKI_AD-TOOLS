# ---------------------------------------------
# Script: Generate-SelfSignedRootAndSignedCert.ps1
# Description: Erstellt ein Root-Zertifikat und signierte Zertifikate für DC1 und optional DC2.
#              Root und DC2-Zertifikat werden remote auf DC2 importiert.
# Author: Robin Kiefer
# ---------------------------------------------

# --- Passwort für Export der PFX-Dateien interaktiv abfragen ---
$pfxPasswordPlain = Read-Host -Prompt "Geben Sie das gewünschte Passwort für die PFX-Dateien ein (sichtbar)"
$pfxPassword = ConvertTo-SecureString $pfxPasswordPlain -AsPlainText -Force

# --- Optional: Zweiten Domain Controller (DC2) interaktiv abfragen ---
$DC2 = Read-Host -Prompt "Optional: Geben Sie den Hostnamen des zweiten DC ein (leer lassen, wenn nicht benötigt)"

# --- Initialisierungsvariablen ---
$domain_name     = $env:userdnsdomain                            # Domänenname des Systems
$dns_name        = "$($env:computername).$domain_name"           # Vollständiger DNS-Name (FQDN)
$date_now        = Get-Date
$extended_date   = $date_now.AddYears(10)                        # Gültigkeit des Zertifikats: 10 Jahre
$root_cert_name  = "PKI-$dns_name-$($date_now.Year)"             # Bezeichnung des Root-Zertifikats
$exportPath      = "C:\Source\Cert"                              # Exportverzeichnis

Write-Host "Starte Zertifikatserstellung für: $root_cert_name"

# --- Sicherstellen, dass das Exportverzeichnis existiert ---
if (-not (Test-Path $exportPath)) {
    Write-Host "Erstelle Exportverzeichnis: $exportPath"
    New-Item -ItemType Directory -Force -Path $exportPath | Out-Null
}

# --- 1. Temporäres, exportierbares Root-Zertifikat im persönlichen Zertifikatsspeicher erstellen ---
Write-Host "Erstelle temporäres exportierbares Root-Zertifikat..."
$rootTemp = New-SelfSignedCertificate `
    -DnsName $root_cert_name `
    -CertStoreLocation "cert:\LocalMachine\My" `
    -KeyExportPolicy Exportable `
    -KeyUsage CertSign, CRLSign `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -TextExtension @("2.5.29.19={text}CA=true") `
    -NotAfter $extended_date

# --- 2. Root-Zertifikat als PFX-Datei mit Passwort exportieren ---
$pfxFile = Join-Path $exportPath "$root_cert_name.pfx"
Export-PfxCertificate -Cert $rootTemp -FilePath $pfxFile -Password $pfxPassword

# --- 3. Signiertes persönliches Zertifikat für DC1 mit Root-Zertifikat als Signer erstellen ---
Write-Host "Erstelle signiertes persönliches Zertifikat für DC1 durch Root-CA"
$personalCert = New-SelfSignedCertificate `
    -DnsName $dns_name `
    -CertStoreLocation "cert:\LocalMachine\My" `
    -Signer $rootTemp `
    -KeyExportPolicy NonExportable `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -NotAfter $extended_date

# --- 4. Optional: Erstelle Zertifikat für DC2 mit Root-CA ---
if ($DC2 -ne "") {
    try {
        $dc2DNS = (Resolve-DnsName $DC2)                        # Versuche, den FQDN per DNS aufzulösen
    } catch {
        Write-Warning "DNS-Auflösung für '$DC2' fehlgeschlagen. Verwende Eingabe direkt."
        $dc2DNS = $DC2                                          # Fallback: verwende eingegebenen Namen
    }

    Write-Host "Erstelle signiertes Zertifikat für DC2 ($dc2DNS) auf DC1"
    $dc2Cert = New-SelfSignedCertificate `
        -DnsName $dc2DNS.Name `
        -CertStoreLocation "cert:\LocalMachine\My" `
        -Signer $rootTemp `
        -KeyExportPolicy Exportable `
        -KeyLength 2048 `
        -KeyAlgorithm RSA `
        -NotAfter $extended_date
}

# --- 5. Temporäres Root-Zertifikat aus dem persönlichen Store löschen ---
Write-Host "Entferne temporäres Zertifikat aus 'My'-Store"
Remove-Item -Path "cert:\LocalMachine\My\$($rootTemp.Thumbprint)" -Force

# --- 6. Importiere PFX wieder als Root-Zertifikat in Trusted Root CA Store, aber nicht exportierbar ---
Write-Host "Importiere Root-Zertifikat in Trusted Root Store (non-exportable)"
$rootFinal = Import-PfxCertificate `
    -FilePath $pfxFile `
    -CertStoreLocation "cert:\LocalMachine\Root" `
    -Password $pfxPassword `
    -Exportable:$false

# --- 7. Exportiere Root-Zertifikat als CER-Datei für Weitergabe oder Verteilung ---
$cerFile = Join-Path $exportPath "$root_cert_name.cer"
Export-Certificate -Cert $rootFinal -FilePath $cerFile

# --- 8. Optional: Exportiere das DC2-Zertifikat als PFX-Datei für Remote-Import ---
if ($DC2 -ne "") {
    $dc2PfxPath = Join-Path $exportPath "$root_cert_name-DC2-Signed.pfx"
    Export-PfxCertificate -Cert $dc2Cert -FilePath $dc2PfxPath -Password $pfxPassword
    # Lösche das Zertifikat aus dem Store, es wird nur auf DC2 benötigt
    Remove-Item -Path "cert:\LocalMachine\My\$($dc2Cert.Thumbprint)" -Force
}

# --- 9. Aufräumen: Entferne Root-Zertifikat aus Intermediate Certification Authorities (wenn vorhanden) ---
Write-Host "Entferne Root-Zertifikat (sofern vorhanden) aus Intermediate Certification Authorities"
Get-ChildItem -Path "cert:\LocalMachine\CA" | Where-Object {
    $_.Thumbprint -eq $rootFinal.Thumbprint
} | Remove-Item -Force

# --- 10. Optional: Kopiere und importiere Zertifikate remote auf DC2 ---
if ($DC2 -ne "") {
    Write-Host "Zweiter DC erkannt: $DC2 - Zertifikate werden verteilt und importiert"

    $remoteCertPath = "\\$DC2\C$\Source\Cert"
    
    # Remote-Verzeichnis vorbereiten
    if (-not (Test-Path $remoteCertPath)) {
        Write-Host "Erstelle Verzeichnis auf DC2: $remoteCertPath"
        Invoke-Command -ComputerName $DC2 -ScriptBlock {
            New-Item -ItemType Directory -Path "C:\Source\Cert" -Force | Out-Null
        }
    }

    # Kopiere CER und DC2-PFX zum Ziel
    Copy-Item -Path $cerFile -Destination $remoteCertPath -Force
    Copy-Item -Path $dc2PfxPath -Destination $remoteCertPath -Force

    # Remote-Import beider Zertifikate auf DC2
    Invoke-Command -ComputerName $DC2 -ScriptBlock {
        param($certName, $securePassword, $rootFinal)

        $cerPath = "C:\Source\Cert\$certName.cer"
        $pfxPath = "C:\Source\Cert\$certName-DC2-Signed.pfx"

        Write-Host "Importiere Root-Zertifikat in Trusted Root Store auf DC2"
        Import-Certificate -FilePath $cerPath -CertStoreLocation "cert:\LocalMachine\Root"

        Write-Host "Importiere signiertes Zertifikat in Personal Store auf DC2"
        Import-PfxCertificate -FilePath $pfxPath -Password $securePassword -CertStoreLocation "cert:\LocalMachine\My" -Exportable:$false

        Write-Host "Entferne Root-Zertifikat (sofern vorhanden) aus Intermediate Certification Authorities"
        Get-ChildItem -Path "cert:\LocalMachine\CA" | Where-Object {
            $_.Thumbprint -eq $rootFinal.Thumbprint
        } | Remove-Item -Force
    } -ArgumentList $root_cert_name, $pfxPassword, $rootFinal
}

# --- Abschlussmeldung & Öffnen der Zielverzeichnisse ---

# Falls DC2 angegeben wurde: entferne Zertifikatspfad
if ($DC2 -ne "") {
    Remove-Item -Path $remoteCertPath -Recurse -Force
    Remove-Item -Path "$exportPath\$root_cert_name-DC2-Signed.pfx"
}

# Öffne lokales Zertifikatsverzeichnis (Exportpfad auf DC1)
Start-Process "explorer.exe" $exportPath

Write-Host "`nVorgang abgeschlossen. Root- und signierte Zertifikate wurden erfolgreich erstellt und verteilt."
