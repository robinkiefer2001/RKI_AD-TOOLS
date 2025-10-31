#User mit Userhomes auslesen aus AD

# Get all AD users
$users = Get-ADUser -Filter * -Property homeDirectory

# Loop through each user and display their homeDirectory path
foreach ($user in $users) {
    $userName = $user.SamAccountName
    $homeDirectory = $user.homeDirectory
    Write-Output "User: $userName, Home Directory: $homeDirectory"
}