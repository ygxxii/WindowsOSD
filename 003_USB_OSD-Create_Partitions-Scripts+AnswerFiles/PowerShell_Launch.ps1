# Script excuted time
$ScriptExecutedTime = Get-Date -UFormat "%Y_%m%d_%H%M%S"
Write-Host "Current Computer Time is: $ScriptExecutedTime"

## Get valid $AnswerFilePath
# Ask user which Answer file to be import
$DriveRootFolderName = "Windows_Installation"

# Get Drive Letters
[System.Collections.ArrayList]$DriveLetterArray = @()
# Get directories to check
[System.Collections.ArrayList]$CheckFolderArray = @()
$DriveLetters = @("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z")
foreach ($DriveLetter in $DriveLetters) {
    $TempPath = $DriveLetter + ":\" + $DriveRootFolderName + "\"
    if (Test-Path $TempPath -PathType 'Container') {
        $DriveLetterArray.Add($DriveLetter) > $null
        $CheckFolderArray.Add($TempPath) > $null
    }
}
# Add script root to the checking directories
# $CheckFolderArray.Add($PSScriptRoot) > $null

# Check the directories, and get the Answer File list
[System.Collections.ArrayList]$AnswerFileAbsolutePathArray = @()
if ($env:firmware_type -eq 'UEFI') {
    foreach ($TempPath in $CheckFolderArray) {
        # The answer file must:
        # * contain "answer"
        # * like "*.xml"
        # * contain "efi" or "gpt"
        $files = Get-ChildItem $TempPath | Where-Object { $_.Name -match "answer" -and $_.Name -like "*.xml" -and ($_.Name -match "efi" -or $_.Name -match "gpt") } | Select-Object FullName
        foreach ($file in $files) {
            $AnswerFileAbsolutePathArray.Add($file.FullName) > $null
        }
    }
}
else {
    foreach ($TempPath in $CheckFolderArray) {
        # The answer file must:
        # * contain "answer"
        # * like "*.xml"
        # * contain "bios" or "mbr"
        $files = Get-ChildItem $TempPath | Where-Object { $_.Name -match "answer" -and $_.Name -like "*.xml" -and ($_.Name -match "bios" -or $_.Name -match "mbr") } | Select-Object FullName
        foreach ($file in $files) {
            $AnswerFileAbsolutePathArray.Add($file.FullName) > $null
        }
    }
}
# Remove duplicate items
$AnswerFileAbsolutePathArray = @($AnswerFileAbsolutePathArray | Select-Object -Unique)

if ($AnswerFileAbsolutePathArray.Count -eq 0) {
    Write-Host "There is no answer file can by imported !" -ForegroundColor Green
    Write-Host "Quit..."
    exit
}
else {
    Write-Host "There is one or more answer files can by imported !"
    if ($AnswerFileAbsolutePathArray.Count -eq 1 -and $PSBoundParameters.ContainsKey('DriveRootFolderName')) {
        $AnswerFilePath = $AnswerFileAbsolutePathArray[0]
    }
    else {
        # Ask user which answer file to import
        Write-Host "Please select an answer file by number:" -ForegroundColor Yellow
        foreach ($AnswerFileAbsolutePath in $AnswerFileAbsolutePathArray) {
            $index = [array]::IndexOf($AnswerFileAbsolutePathArray, $AnswerFileAbsolutePath)
            Write-Host "    " $index "-" $AnswerFileAbsolutePath -ForegroundColor Yellow
        }
        [ValidateScript( { $_ -ge 0 -and $_ -lt $AnswerFileAbsolutePathArray.Count })]
        [int]$number = Read-Host "Press the number to select an answer file"
        Write-Host "You chose:" $AnswerFileAbsolutePathArray[$number]
        $AnswerFilePath = $AnswerFileAbsolutePathArray[$number]
    }
}

# Relative Path to Absolute Path
$AnswerFilePath = Resolve-Path -Path $AnswerFilePath
Write-Host "The source answer file path is:" $AnswerFilePath -ForegroundColor Green

# Create Folder to backup source Answer file
$AnswerFileBaseName = (Get-Item $AnswerFilePath).BaseName
$AnswerFileDirectoryName = (Get-Item $AnswerFilePath).DirectoryName
$NewContainer = $AnswerFileDirectoryName + "\" + $ScriptExecutedTime + "-" + $AnswerFileBaseName + "\"
if (-not (Test-Path $NewContainer -PathType Container)) {
    Write-Host "New Folder created:" $NewContainer
    New-Item -ItemType directory -Path $NewContainer > $null
}
# Export Get-Disk Output to Folder
$GetDiskExportCsvPath = $NewContainer + "1_Get_Disk.csv"
Get-Disk | Export-Csv -Path $GetDiskExportCsvPath
Write-Host "Get-Disk output saved:" $GetDiskExportCsvPath -ForegroundColor Green

# Backup origin Answer File to Folder
$AnswerFileOriginBackupPath = $NewContainer + "2_AnswerFile_OriginBackup.xml"
Copy-Item $AnswerFilePath -Destination $AnswerFileOriginBackupPath > $null

# Modify the Answer File
Powershell.exe -Executionpolicy bypass -Nologo -Noprofile -File "$PSScriptRoot\newcomputer_answerfile_partitiontable_modifier.ps1" "-AnswerFilePath" "$AnswerFilePath" "-DataPartitionSizeInMB" "51200" "-DriveRootFolderName" "$DriveRootFolderName"
# Backup modified Answer File to Folder
$AnswerFileModifiedPath = $env:TEMP + "\tempAnswerFile.xml"
$AnswerFileModifiedBackupPath = $NewContainer + "3_AnswerFile_ModifiedBackup.xml"
Copy-Item $AnswerFileModifiedPath -Destination $AnswerFileModifiedBackupPath > $null

# Run Windows Setup with Answer File
# Start-Process -FilePath "$env:SystemDrive\Setup.exe" -ArgumentList "/unattend: `"$AnswerFileModifiedPath`""
cmd.exe /k "$env:SystemDrive\Setup.exe /unattend:$AnswerFileModifiedPath"