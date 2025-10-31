# ========================================================================
# Funktion: Rekursiv alle Benutzer einer AD-Gruppe inkl. verschachtelter Gruppen ermitteln
# ========================================================================

function Get-AllGroupUsers {
    param (
        [string]$GroupName  # Eingabe: SamAccountName der Quellgruppe
    )

    # Alle Mitglieder der angegebenen Gruppe abrufen
    $members = Get-ADGroupMember -Identity $GroupName -ErrorAction SilentlyContinue

    foreach ($member in $members) {
        if ($member.objectClass -eq "user") {
            # Direkte Benutzer zurückgeben
            $member
        }
        elseif ($member.objectClass -eq "group") {
            # Rekursion: Mitglieder der verschachtelten Gruppe holen
            Get-AllGroupUsers -GroupName $member.SamAccountName
        }
    }
}

# ========================================================================
# Definition der Quellgruppen (mit Platzhaltergruppe)
# ========================================================================

$groupsToQuery = @(
    "GRUPPENNAME_QUELLE"  # Beispiel: "G_G_IT_SUPPORT"
)

# ========================================================================
# Alle Benutzer aus den definierten Quellgruppen sammeln
# ========================================================================

$allUsers = foreach ($group in $groupsToQuery) {
    Get-AllGroupUsers -GroupName $group
}

# Doppelte Benutzer anhand SamAccountName entfernen
$distinctUsers = $allUsers | Sort-Object -Property SamAccountName -Unique

# ========================================================================
# Ausgabe zur Kontrolle (optional)
# ========================================================================

$distinctUsers | Select-Object Name, SamAccountName

# ========================================================================
# Benutzer der Zielgruppe hinzufügen
# ========================================================================

$zielgruppe = "GRUPPENNAME_ZIEL"  # Beispiel: "G_ALL_SUPPORT"

$distinctUsers | ForEach-Object {
    Add-ADGroupMember -Identity $zielgruppe -Members $_ -ErrorAction Stop
}

# ========================================================================
# Validierung: Prüfung ob alle Benutzer korrekt in der Zielgruppe sind
# ========================================================================

# Mitglieder der Zielgruppe abrufen
$targetGroupMembers = Get-ADGroupMember -Identity $zielgruppe -Recursive | Where-Object { $_.objectClass -eq "user" }

# Prüfen, ob jemand fehlt
$missingUsers = $distinctUsers | Where-Object {
    $user = $_
    -not ($targetGroupMembers | Where-Object { $_.SamAccountName -eq $user.SamAccountName })
}

# Ausgabe je nach Ergebnis
if ($missingUsers.Count -gt 0) {
    Write-Host "Folgende Benutzer fehlen in der Zielgruppe $zielgruppe"
    $missingUsers | Select-Object Name, SamAccountName | Format-Table -AutoSize
    exit 1
} else {
    Write-Host "Alle Benutzer sind korrekt Mitglied der Zielgruppe $zielgruppe."
    exit 0
}
