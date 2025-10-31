$allServers = Get-ADComputer -Filter * -Property OperatingSystem |
  Where-Object { $_.OperatingSystem -like 'Windows Server*' } |
  Select-Object -ExpandProperty Name

  <# ===============================================
 Funktionen: SNMP PermittedManagers auslesen & ergaenzen
 Voraussetzungen:
 - WinRM/PS Remoting erreichbar
 - AD-Modul optional (nur fuer Beispiel-Serverliste)
 - SNMP Dienst auf Zielsystem installiert, sonst "nicht installiert"
================================================ #>

function Get-SnmpManagers {
  <#
    .SYNOPSIS
      Liest SNMP PermittedManagers remote aus.
    .PARAMETER computerName
      Zielserver (einzelner Name oder Array). Standard: lokaler Host.
    .OUTPUTS
      PSCustomObject: serverName, snmpActive, snmpManagers, pathUsed
  #>
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string[]] $computerName = $env:COMPUTERNAME
  )
  process {
    foreach ($cn in $computerName) {
      $remoteBlock = {
        # Hilfsfunktion: alle Wertdaten (ausser Default) eines Registry-Schluessels
        function Get-RegistryValueDataList {
          param([string]$path)
          if (-not (Test-Path -LiteralPath $path)) { return @() }
          $regKey = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
          if (-not $regKey) { return @() }
          $valueNames = $regKey.GetValueNames() | Where-Object { $_ -ne '(default)' }
          foreach ($valueName in $valueNames) { $regKey.GetValue($valueName) }
        }

        $snmpService = Get-Service -Name SNMP -ErrorAction SilentlyContinue
        if (-not $snmpService) {
          return [PSCustomObject]@{
            serverName   = $env:COMPUTERNAME
            snmpActive   = $false
            snmpManagers = $null
            pathUsed     = $null
          }
        }

        # Pfade: GPO bevorzugt, sonst lokal
        $paths = @(
          'HKLM:\SOFTWARE\Policies\SNMP\Parameters\PermittedManagers',
          'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers'
        )
        $targetPath = ($paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
        if (-not $targetPath) { $targetPath = $paths[1] }

        $currentManagers = @()
        foreach ($p in $paths) { $currentManagers += Get-RegistryValueDataList -Path $p }
        $currentManagers = $currentManagers | Where-Object { $_ } | Select-Object -Unique

        [PSCustomObject]@{
          serverName   = $env:COMPUTERNAME
          snmpActive   = $true
          snmpManagers = if ($currentManagers) { ($currentManagers | Sort-Object) -join ', ' } else { $null }
          pathUsed     = $targetPath
        }
      }

      Invoke-Command -ComputerName $cn -ScriptBlock $remoteBlock -ErrorAction SilentlyContinue
    }
  }
}

function Add-SnmpManager {
  param(
    [string[]]$computerName,
    [string]$manager,
    [bool]$restart
  )

  $remoteBlock = {
    param($manager, $restart)

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers'

    # Sicherstellen, dass der Key existiert
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }

    # Aktuelle Werte lesen
    $key = Get-Item $path
    $names = $key.GetValueNames() | Where-Object { $_ -ne '(default)' }
    $values = $names | ForEach-Object { $key.GetValue($_) }

    # Wenn schon drin -> überspringen
    if ($values -contains $manager) {
      return "$env:COMPUTERNAME: $manager bereits vorhanden"
    }

    # Nächsten Index bestimmen
    $next = if ($names) { ($names | ForEach-Object {[int]$_} | Measure-Object -Maximum).Maximum + 1 } else { 1 }

    # Neuen Manager schreiben
    New-ItemProperty -Path $path -Name $next -Value $manager -PropertyType String -Force | Out-Null

    # SNMP-Dienst neu starten, damit Änderung wirksam wird
    if($restart -eq $true){
        Restart-Service -Name SNMP -Force
    }

    return "$env:COMPUTERNAME: $manager hinzugefügt (Index $next)"
  }

  Invoke-Command -ComputerName $computerName -ScriptBlock $remoteBlock -ArgumentList $manager, $restart
}

function Remove-SnmpManager {
    param(
        [string[]]$computerName,
        [string]$manager,
        [bool]$restart
    )

    $remoteBlock = {
        param($manager, $restart)

        $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers'

        if (-not (Test-Path $path)) {
            return "$env:COMPUTERNAME: Key nicht gefunden ($path)"
        }

        $key    = Get-Item $path
        $names  = $key.GetValueNames() | Where-Object { $_ -ne '(default)' }
        $values = $names | ForEach-Object { [PSCustomObject]@{ Name=$_; Value=$key.GetValue($_) } }

        # passenden Eintrag suchen
        $match = $values | Where-Object { $_.Value -ieq $manager }
        if (-not $match) {
            return "$env:COMPUTERNAME: $manager nicht vorhanden"
        }

        # Eintrag entfernen
        foreach ($m in $match) {
            Remove-ItemProperty -Path $path -Name $m.Name -ErrorAction SilentlyContinue
        }

        # optional Dienst neu starten
        if ($restart -eq $true) {
            Restart-Service -Name SNMP -Force
        }

        return "$env:COMPUTERNAME: $manager entfernt"
    }

    Invoke-Command -ComputerName $computerName -ScriptBlock $remoteBlock -ArgumentList $manager, $restart
}
