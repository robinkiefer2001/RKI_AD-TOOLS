# Servername
$serverName = hostname

# Pfad zur CSV-Datei
$csvPath = "$env:USERPROFILE\Desktop\SharePermissions.csv"

# Initialisiere die CSV-Datei
"ShareName,Path,Account,Access" | Out-File -FilePath $csvPath

# Hole alle Freigaben auf dem Server
$shares = Get-WmiObject -Class Win32_Share 

foreach ($share in $shares) {
    $acl = Get-Acl -Path "\\$serverName\$($share.Name)"
    foreach ($access in $acl.Access) {
        $line = "$($share.Name),$($share.Path),$($access.IdentityReference),$($access.FileSystemRights)"
        $line | Out-File -FilePath $csvPath -Append
    }
}

Write-Host "Berechtigungen wurden in die Datei $csvPath geschrieben."