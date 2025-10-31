# ========================================
# Konfigurierbare Variablen (für verschiedene Umgebungen anpassbar)
# ========================================

$DC = "dc01"  # Name des Domain Controllers, z. B. "dc01", "adserver01", "domaincontroller-prod"
$OU = "OU=Benutzer,OU=StandortXY,DC=firma,DC=intern"  # Distinguished Name der OU, in der sich die Benutzerobjekte befinden

$userHomePathUNC   = "\\fileserver01\D$\Benutzerverzeichnisse"  # UNC-Pfad zum Verzeichnis auf dem Fileserver
$userHomePathLocal = "D:\Benutzerverzeichnisse"  # Lokaler Pfad auf dem Fileserver (wird für Set-Acl verwendet)

$smbShareSufix     = "Home-"  # Präfix für den Share-Namen, z. B. ergibt "Home-max.mustermann$" für Benutzerordner
$domainAdminName   = "svc-support"  # Name des technischen Support- oder Service-Accounts, der ebenfalls Zugriff erhalten soll
$domainName        = $env:USERDOMAIN  # NetBIOS-Domänenname (z. B. "INTRANET", "FIRMA", "HQDOMAIN")

# =====================================================
# Benutzerliste aus der definierten OU via DC abrufen
# =====================================================

$users = Invoke-Command -ComputerName "$DC" -ScriptBlock {
    param($OU)
    # Abruf aller Benutzer aus der angegebenen OU mit benötigten Attributen
    Get-ADUser -Filter * -SearchBase $OU -Properties DisplayName, SamAccountName, UserPrincipalName
} -ArgumentList $OU

# =====================================================
# Vorhandene Userhome-Verzeichnisse auf dem Fileserver prüfen
# =====================================================

$userHomesExisting = Get-ChildItem -Path $userHomePathUNC -Directory | Select-Object -ExpandProperty Name

# =====================================================
# Hauptverarbeitung: Pro Benutzer prüfen, erstellen, ACL setzen
# =====================================================

foreach ($user in $users) {

    # Aus UserPrincipalName den Login-Namen extrahieren (z. B. "max.mustermann" aus "max.mustermann@domain.tld")
    $folderName = $user.UserPrincipalName -split "@"
    $folderName = $folderName[0]

    $currentUserDisplayName = $user.DisplayName       # Für die Lesbarkeit in der Konsole
    $userAccount = $user.SamAccountName               # Konto-Name für ACLs und Freigaben

    # Prüfen, ob das Userhome bereits existiert
    if ($userHomesExisting -contains $folderName) {
        Write-Host "$currentUserDisplayName hat ein Userhome in $userHomePathUNC\$folderName"
    }
    else {
        Write-Host "$currentUserDisplayName hat kein Userhome – wird erstellt..."

        # Zielpfad für das neue Benutzerverzeichnis auf dem Fileserver
        $folderPath = "$userHomePathLocal\$folderName"

        # Share-Name: z. B. "Home-max.mustermann$"
        $newShare = "$smbShareSufix$folderName`$"

        # ============================================
        # Ordner erstellen, wenn nicht vorhanden
        # ============================================
        if (-not (Test-Path $folderPath)) {
            New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
        }

        # ============================================
        # SMB-Share prüfen und erstellen (wenn nötig)
        # ============================================
        if (-not (Get-SmbShare -Name $newShare -ErrorAction SilentlyContinue)) {
            New-SmbShare -Name $newShare -Path $folderPath -ChangeAccess "NT AUTHORITY\Authenticated Users"
        }

        # ============================================
        # NTFS-Berechtigungen definieren
        # ============================================

        # Neues leeres ACL-Objekt erzeugen
        $acl = New-Object System.Security.AccessControl.DirectorySecurity

        # Standardrechte für Vollzugriff
        $rights      = [System.Security.AccessControl.FileSystemRights]"FullControl"
        $inherit     = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
        $propagation = [System.Security.AccessControl.PropagationFlags]::None
        $type        = [System.Security.AccessControl.AccessControlType]::Allow

        # Berechtigungsregeln definieren:
        $rules = @(
            # SYSTEM: immer Vollzugriff
            (New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList "SYSTEM", $rights, $inherit, $propagation, $type),

            # Benutzer selbst bekommt Zugriff
            (New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList "$domainName\$userAccount", $rights, $inherit, $propagation, $type),

            # Technisches Admin- oder Supportkonto bekommt Zugriff (z. B. für Fernwartung oder 2nd-Level)
            (New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList "$domainName\$domainAdminName", $rights, $inherit, $propagation, $type)
        )

        # Berechtigungen zur ACL hinzufügen
        foreach ($rule in $rules) {
            $acl.AddAccessRule($rule)
        }

        # ACL auf den Ordner anwenden
        Set-Acl -Path $folderPath -AclObject $acl
    }
}
