$siteUrl = Read-Host -Prompt "Geben sie die Site URL ein https://cotoso.sharepoint.com/sites/MeineSeite"

Install-Module PnP.PowerShell -Scope CurrentUser
Import-Module PnP.PowerShell

Connect-PnPOnline -Url $siteUrl -UseWebLogin


#Function to upload all files from a local folder to SharePoint Online Folder
Function Upload-PnPFolder($LocalFolderPath, $TargetFolderURL)
{
    Write-host "Processing Folder:"$LocalFolderPath -f Yellow
    #Get All files and SubFolders from the local disk
    $Files = Get-ChildItem -Path $LocalFolderPath -File
 
    #Ensure the target folder
    Resolve-PnPFolder -SiteRelativePath $TargetFolderURL | Out-Null
 
    #Upload All files from the local folder to SharePoint Online Folder
    ForEach ($File in $Files)
    {
        Add-PnPFile -Path "$($File.Directory)\$($File.Name)" -Folder $TargetFolderURL -Values @{"Title" = $($File.Name)} | Out-Null
        Write-host "`tUploaded File:"$File.FullName -f Green
    }
}

$LocalFolderPath = Read-Host -Prompt "Geben sie den Lokalen Ordnerpfad an"
$TargetFolderURL = Read-Host -Prompt "Geben sie die Zielordner URL an"

#Call the function to upload the Root Folder
Upload-PnPFolder -LocalFolderPath $LocalFolderPath -TargetFolderURL $TargetFolderURL
 
#Get all Folders from given source path
Get-ChildItem -Path $LocalFolderPath -Recurse -Directory | ForEach-Object {
    $FolderToUpload = ($TargetFolderURL+$_.FullName.Replace($LocalFolderPath,[string]::Empty)).Replace("\","/")
    Upload-PnPFolder -LocalFolderPath $_.FullName -TargetFolderURL $FolderToUpload
}

