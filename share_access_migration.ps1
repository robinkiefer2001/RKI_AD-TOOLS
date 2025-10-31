## Share Access Enumeration v1
### Author RKI

# Variable Definitions
$oldFS = Read-Host -Prompt "Geben Sie den FQDN des alten Fileservers ein"
$oldFSsession = New-CimSession -ComputerName $oldFS
$oldShares = (Get-SmbShare -CimSession $oldFSsession)
$oldSharesACLs = foreach($sa in $oldShares){
    Get-SmbShareAccess -CimSession $oldFSsession -Name $sa.Name
}

$lang = Read-Host -Prompt "Geben sie DE oder EN ein"

# Functions
function test-isgroup {
    param(
        $nameVal
    )

    # Überprüft, ob der Name einer AD-Gruppe entspricht
    $gQuerryReturn = Get-ADGroup -Identity $nameVal -ErrorAction SilentlyContinue

    if ($gQuerryReturn -ne $null) {
            return $true
        } 
         
     else {
            return $false
        }   
}

function get-ShareUsers {
    param(
        [Parameter(Mandatory=$true)]$acls,
        [Parameter(Mandatory=$true)]$shares
    )

    # Classes
    class UserObj {
        [string] $uName
        [string] $uAccessControlType
        [string] $uAccessRight
        [string] $uNtfsAccess
        [string] $uNtfsType

        UserObj([string]$uName, [string]$uAccessControlType, [string]$uAccessRight, [string]$uNtfsType, [string]$uNtfsAccess) {
            $this.uName = $uName
            $this.uAccessControlType = $uAccessControlType
            $this.uAccessRight = $uAccessRight
            $this.uNtfsType = $uNtfsType
            $this.uNtfsAccess = $uNtfsAccess
        }
    }

    class ShareObj {
        [String] $sName
        [String] $sPath
        [UserObj[]] $sPermissions

        ShareObj([string]$sName, [String]$sPath, [UserObj[]]$sPermissions) {
            $this.sName = $sName
            $this.sPath = $sPath
            $this.sPermissions = $sPermissions
        }
    }
    

    $allShareObj = @()
    $allUserObj = @()
    $allAcls = @()
    $allNTFonShare = @()


$oldFSsessionPS = New-PSSession -ComputerName $oldFS

$oldShares | ForEach-Object {
    $sa = $_
    $tempPath = $sa.Path
    if ($tempPath -ne $null -and $tempPath -ne "") {

            $acl = Invoke-Command -Session $oldFSsessionPS -ScriptBlock {
                param($param1)
                $localPath = Convert-Path -Path $param1
                Get-Acl -Path $localPath
            } -ArgumentList $tempPath
            $allAcls += $acl
    }
}
Remove-PSSession -Session $oldFSsessionPS


foreach($np in $allAcls){
    $tempDelimiter = "::"
    $npAccessToString = $np.AccessToString

    $npSharePath = $np.Path -split $tempDelimiter
    $npSharePath = $npSharePath[1]

    $npShareObject = $oldShares | Where-Object { $_.Path -eq $npSharePath }

    $npShareName = $npShareObject.Name
}


    foreach($entry in $acls){
        $tempName = $entry.AccountName

        if($tempName.Contains("\") -eq $true) {
            $tempName = $tempName.Split("\")[1]
            $aclName = $tempName
        } else {
            $aclName = $tempName
        }

        if($aclName -eq "Administrators" -and $lang -eq "DE"){$aclName = "Administratoren"}
        if($aclName -eq "Backup Operators" -and $lang -eq "DE"){$aclName = "Sicherungs-Operatoren"}

        # Behandlung von "Jeder", "Administratoren" und "Sicherungs-Operatoren"
        if ($aclName -eq "Jeder" -or $aclName -eq "Everyone" -or $aclName -eq "Administratoren" -or $aclName -eq "Sicherungs-Operatoren") {
            
            $newUserObj = [UserObj]::new($aclName, $entry.AccessControlType, $entry.AccessRight)

            # Überprüfen, ob UserObj bereits existiert
            if ($allUserObj.Where({$_.uName -eq $newUserObj.uName -and $_.uAccessControlType -eq $newUserObj.uAccessControlType -and $_.uAccessRight -eq $newUserObj.uAccessRight}).Count -eq 0) {
                $allUserObj += $newUserObj
            }

            foreach($share in $shares){
                $existingShareObj = $allShareObj | Where-Object {$_.sName -eq $share.Name}

                if ($existingShareObj) {
                    # Überprüfen, ob UserObj bereits in ShareObj existiert
                    if ($existingShareObj.sPermissions.Where({$_.uName -eq $newUserObj.uName -and $_.uAccessControlType -eq $newUserObj.uAccessControlType -and $_.uAccessRight -eq $newUserObj.uAccessRight}).Count -eq 0) {
                        $existingShareObj.sPermissions += $newUserObj
                    }
                } else {
                    $newShareObj = [ShareObj]::new(
                        $share.Name,
                        $share.Path,
                        @($newUserObj)
                    )
                    $allShareObj += $newShareObj
                }
            }
        }
        elseif($aclName -eq "INTERACTIVE"){Write-Host "Interaktive Gruppe aktiv" -ForegroundColor Yellow}
        elseif($aclName -match "S-1-5-21-\d+-\d+-\d+-\d+"){Write-Host "Gelöschtes Objekt" -ForegroundColor Yellow}
        else{
            if(test-isgroup -nameVal $aclName -eq $true){
                $tempGroupMembers = Get-ADGroupMember -Identity $aclName

                foreach($gM in $tempGroupMembers){
                    $tempPermissions = @{
                        AccessControlType = $entry.AccessControlType
                        accessRight = $entry.AccessRight
                    }

                    $tempValues = $tempPermissions.Values
                    $tempValues = $tempValues -split "`n"

                    $tempAccessType = $tempValues[0]
                    $tempAccessRight = $tempValues[1]

                    $newUserObj = [UserObj]::new($gM.SamAccountName, $tempAccessType, $tempAccessRight)

                    # Überprüfen, ob UserObj bereits existiert
                    if ($allUserObj.Where({$_.uName -eq $newUserObj.uName -and $_.uAccessControlType -eq $newUserObj.uAccessControlType -and $_.uAccessRight -eq $newUserObj.uAccessRight}).Count -eq 0) {
                        $allUserObj += $newUserObj
                    }

                    foreach($share in $shares){
                        $existingShareObj = $allShareObj | Where-Object {$_.sName -eq $share.Name}

                        if ($existingShareObj) {
                            # Überprüfen, ob UserObj bereits in ShareObj existiert
                            if ($existingShareObj.sPermissions.Where({$_.uName -eq $newUserObj.uName -and $_.uAccessControlType -eq $newUserObj.uAccessControlType -and $_.uAccessRight -eq $newUserObj.uAccessRight}).Count -eq 0) {
                                $existingShareObj.sPermissions += $newUserObj
                            }
                        } else {
                            $newShareObj = [ShareObj]::new(
                                $share.Name,
                                $share.Path,
                                @($newUserObj)
                            )
                            $allShareObj += $newShareObj
                        }
                    }
                }
            } else {
                $tempUser = Get-ADUser -Identity $tempName -ErrorAction SilentlyContinue
                if ($tempUser){
                    $newUserObj = [UserObj]::new($tempUser.SamAccountName, $entry.AccessControlType, $entry.AccessRight)

                    # Überprüfen, ob UserObj bereits existiert
                    if ($allUserObj.Where({$_.uName -eq $newUserObj.uName -and $_.uAccessControlType -eq $newUserObj.uAccessControlType -and $_.uAccessRight -eq $newUserObj.uAccessRight}).Count -eq 0) {
                        $allUserObj += $newUserObj
                    }

                    $share = $shares | Where-Object {$_.Name -eq $entry.ShareName}

                    if ($share) {
                        $existingShareObj = $allShareObj | Where-Object { $_.sName -eq $share.Name }

                        if ($existingShareObj) {
                            # Überprüfen, ob UserObj bereits in ShareObj existiert
                            if ($existingShareObj.sPermissions.Where({$_.uName -eq $newUserObj.uName -and $_.uAccessControlType -eq $newUserObj.uAccessControlType -and $_.uAccessRight -eq $newUserObj.uAccessRight}).Count -eq 0) {
                                $existingShareObj.sPermissions += $newUserObj
                            }
                        } else {
                            $newShareObj = [ShareObj]::new($share.Name, $share.Path, @($newUserObj))
                            $allShareObj += $newShareObj
                        }
                    }
                }
            }
        }
    }
    return $allShareObj
}

# Main
$SharesAndPersmissions = get-ShareUsers -acls $oldSharesACLs -shares $oldShares

$oldShareNtfsAcls | select AccessToString | fl


