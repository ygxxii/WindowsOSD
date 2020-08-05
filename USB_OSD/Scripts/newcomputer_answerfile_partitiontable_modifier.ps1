#requires -version 4
<#
.SYNOPSIS
  Modify <DiskConfiguration> settings in answer file. and generate a CreatePartitions.txt file for DiskPart.

.DESCRIPTION
  Deployment Scenario: New Computer. All Disks on the target computer will be wiped, except USB Drive.

  1. Make <DiskConfiguration> settings in answer file properly
  2. Check if other settings in answer file are set
  3. Generate CreatePartitions.txt file for DiskPart

  MBR Disk Partition Table(w/ Data Partition):
    | Partition 1      | Partition 2    | Partition 3              | Partition 4    |
    |------------------|----------------|--------------------------|----------------|
    | System Partition | Boot Partition | Recovery Tools Partition | Data Partition |
    | Order=1          | Order=2        | Order=3                  | Order=4        |
    | Type=Primary     | Type=Primary   | Type=Primary             | Type=Primary   |
    | -                | -              | -                        | Extend=true    |
    | Size=xxxMB       | Size=xxxMB     | Size=xxxMB               | -              |

  MBR Disk Partition Table(w/o Data Partition):
    | Partition 1      | Partition 2    | Partition 3              |
    |------------------|----------------|--------------------------|
    | System Partition | Boot Partition | Recovery Tools Partition |
    | Order=1          | Order=2        | Order=3                  |
    | Type=Primary     | Type=Primary   | Type=Primary             |
    | -                | -              | Extend=true              |
    | Size=xxxMB       | Size=xxxMB     | -                        |

  GPT Disk Partition Table(w/ Data Partition):
    | Partition 1          | Partition 2                  | Partition 3    | Partition 4              | Partition 5    |
    |----------------------|------------------------------|----------------|--------------------------|----------------|
    | EFI System Partition | Microsoft Reserved Partition | Boot Partition | Recovery Tools Partition | Data Partition |
    | Order=1              | Order=2                      | Order=3        | Order=4                  | Order=5        |
    | Type=EFI             | Type=MSR                     | Type=Primary   | Type=Primary             | Type=Primary   |
    | -                    | -                            | -              | -                        | Extend=true    |
    | Size=xxxMB           | Size=xxxMB                   | Size=xxxMB     | Size=xxxMB               | -              |

  GPT Disk Partition Table(w/o Data Partition):
    | Partition 1          | Partition 2                  | Partition 3    | Partition 4              |
    |----------------------|------------------------------|----------------|--------------------------|
    | EFI System Partition | Microsoft Reserved Partition | Boot Partition | Recovery Tools Partition |
    | Order=1              | Order=2                      | Order=3        | Order=4                  |
    | Type=EFI             | Type=MSR                     | Type=Primary   | Type=Primary             |
    | -                    | -                            | -              | Extend=true              |
    | Size=xxxMB           | Size=xxxMB                   | Size=xxxMB     | -                        |

  GPT Disk Partition Table(w/ Data Partition, w/o Microsoft Reserved Partition ):
    | Partition 1          | Partition 3    | Partition 4              | Partition 5    |
    |----------------------|----------------|--------------------------|----------------|
    | EFI System Partition | Boot Partition | Recovery Tools Partition | Data Partition |
    | Order=1              | Order=2        | Order=3                  | Order=4        |
    | Type=EFI             | Type=Primary   | Type=Primary             | Type=Primary   |
    | -                    | -              | -                        | Extend=true    |
    | Size=xxxMB           | Size=xxxMB     | Size=xxxMB               | -              |

  GPT Disk Partition Table(w/o Data Partition, w/o Microsoft Reserved Partition ):
    | Partition 1          | Partition 3    | Partition 4              |
    |----------------------|----------------|--------------------------|
    | EFI System Partition | Boot Partition | Recovery Tools Partition |
    | Order=1              | Order=2        | Order=3                  |
    | Type=EFI             | Type=Primary   | Type=Primary             |
    | -                    | -              | Extend=true              |
    | Size=xxxMB           | Size=xxxMB     | -                        |

.PARAMETER <Parameter_Name>
  <Brief description of parameter input required. Repeat this attribute if required>

.NOTES
  Version:        1.0
  Author:         ygxxii
  Creation Date:  2020/08/01
  Purpose/Change: Initial script development

.EXAMPLE
  ./answer_file_Partition_table_modifier.ps1 -AnswerFilePath "myAutounattend.xml"


#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------

# TODO
# * ParameterSetName

[CmdletBinding()]
Param (
    # file path to AnswerFile
    [Parameter(Mandatory = $false)]
    [ValidateScript({Test-Path $_ -PathType 'Leaf'})]
    [string]
    $AnswerFilePath,

    # Specify the firmware type
    [Parameter(Mandatory = $false)]
    [ValidateSet('Legacy', 'UEFI')]
    [string]
    $FirmwareType=$env:firmware_type,

    # Specify the Boot Partition DiskID
    [Parameter(Mandatory = $false)]
    [int]
    $BootPartitionDiskID,

    # (EFI) System Partition size(MB, >=100MB)
    [Parameter(Mandatory = $false)]
    [ValidateScript({$_ -ge 100})]
    [int]
    $SystemPartitionSizeInMB=300,

    # Microsoft Reserved Partition size(MB, =0, >=16MB, <=128MB)
    # Microsoft Reserved Partition - Wikipedia https://en.wikipedia.org/wiki/Microsoft_Reserved_Partition
    [Parameter(Mandatory = $false)]
    [ValidateScript( { $_ -eq 0 -or ($_ -ge 16 -and $_ -le 128) } )]
    [int]
    $MicrosoftReservedPartitionSizeInMB=128,

    # Recovery Tools Partition size(MB, >=300MB)
    [Parameter(Mandatory = $false)]
    [ValidateScript({$_ -ge 300})]
    [int]
    $RecoveryToolsPartitionSizeInMB=1000,

    # Data Partition size(MB, =0, >=5GB)
    [Parameter(Mandatory = $false)]
    [ValidateScript( { $_ -eq 0 -or  $_ -ge 5120 } )]
    [int]
    $DataPartitionSizeInMB=0,

    # name of the folder under drive root
    [Parameter(Mandatory = $false)]
    [string]
    $DriveRootFolderName="Windows_Installation"
    # $DriveRootFolderName is set : do not ask user which answer file to be imported, if there is only 1 answer file is found.
)

# Write-Host "List specified script parameters:"
# $PSCmdlet.ParameterSetName
# $PSBoundParameters

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
# $ErrorActionPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'
#Set Debug to Continue
$DebugPreference = 'Continue'

#----------------------------------------------------------[Declarations]----------------------------------------------------------

# Script excuted time
$ScriptExecutedTime = Get-Date -UFormat "%Y_%m%d_%H%M%S"

# Templates:
## MBR [Boot Partition Disk] Partitions:
### <DiskConfiguration>:
$TemplateMBRDiskConfiguration = @"
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <DiskConfiguration>
            <WillShowUI>OnError</WillShowUI>
            <Disk wcm:action="add">
                <CreatePartitions>
                    <CreatePartition wcm:action="add">
                        <Order>1</Order>
                        <Size>300</Size>
                        <Type>Primary</Type>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                        <Order>2</Order>
                        <Size>51200</Size>
                        <Type>Primary</Type>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                        <Order>3</Order>
                        <Type>Primary</Type>
                        <Size>1000</Size>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                        <Order>4</Order>
                        <Extend>true</Extend>
                        <Type>Primary</Type>
                    </CreatePartition>
                </CreatePartitions>
                <ModifyPartitions>
                    <ModifyPartition wcm:action="add">
                        <Active>true</Active>
                        <Format>NTFS</Format>
                        <Label>System Reserved</Label>
                        <Order>1</Order>
                        <PartitionID>1</PartitionID>
                        <TypeID>0x07</TypeID>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                        <Format>NTFS</Format>
                        <Label>Windows</Label>
                        <Letter>C</Letter>
                        <PartitionID>2</PartitionID>
                        <Order>2</Order>
                        <TypeID>0x07</TypeID>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                        <Format>NTFS</Format>
                        <Label>WinRE</Label>
                        <PartitionID>3</PartitionID>
                        <Order>3</Order>
                        <TypeID>0x27</TypeID>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                        <Format>NTFS</Format>
                        <Label>Data</Label>
                        <Letter>D</Letter>
                        <Order>4</Order>
                        <PartitionID>4</PartitionID>
                        <TypeID>0x07</TypeID>
                    </ModifyPartition>
                </ModifyPartitions>
                <DiskID>0</DiskID>
                <WillWipeDisk>true</WillWipeDisk>
            </Disk>
            <Disk wcm:action="add">
                <CreatePartitions>
                    <CreatePartition wcm:action="add">
                        <Order>1</Order>
                        <Size>300</Size>
                        <Type>Primary</Type>
                    </CreatePartition>
                </CreatePartitions>
                <ModifyPartitions>
                    <ModifyPartition wcm:action="add">
                        <Active>true</Active>
                        <Format>NTFS</Format>
                        <Label>System</Label>
                        <Order>1</Order>
                        <PartitionID>1</PartitionID>
                    </ModifyPartition>
                </ModifyPartitions>
                <DiskID>1</DiskID>
                <WillWipeDisk>true</WillWipeDisk>
            </Disk>
        </DiskConfiguration>
    </component>
  </settings>
</unattend>
"@

### <ImageInstall>:
$TemplateMBRImageInstall = @"
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <ImageInstall>
            <OSImage>
                <InstallTo>
                    <DiskID>0</DiskID>
                    <PartitionID>2</PartitionID>
                </InstallTo>
                <WillShowUI>OnError</WillShowUI>
            </OSImage>
        </ImageInstall>
    </component>
  </settings>
</unattend>
"@

## GPT [Boot Partition Disk] Partitions:
### <DiskConfiguration>:
$TemplateGPTDiskConfiguration = @"
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <DiskConfiguration>
            <WillShowUI>OnError</WillShowUI>
            <Disk wcm:action="add">
                <CreatePartitions>
                    <CreatePartition wcm:action="add">
                        <Order>1</Order>
                        <Size>300</Size>
                        <Type>EFI</Type>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                        <Order>2</Order>
                        <Size>128</Size>
                        <Type>MSR</Type>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                        <Order>3</Order>
                        <Type>Primary</Type>
                        <Size>51200</Size>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                        <Order>4</Order>
                        <Type>Primary</Type>
                        <Size>1000</Size>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                        <Order>5</Order>
                        <Extend>true</Extend>
                        <Type>Primary</Type>
                    </CreatePartition>
                </CreatePartitions>
                <ModifyPartitions>
                    <ModifyPartition wcm:action="add">
                        <Format>FAT32</Format>
                        <Label>System</Label>
                        <Order>1</Order>
                        <PartitionID>1</PartitionID>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                        <PartitionID>2</PartitionID>
                        <Order>2</Order>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                        <Format>NTFS</Format>
                        <Label>Windows</Label>
                        <PartitionID>3</PartitionID>
                        <Order>3</Order>
                        <Letter>C</Letter>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                        <Format>NTFS</Format>
                        <Label>WinRE</Label>
                        <Order>4</Order>
                        <PartitionID>4</PartitionID>
                        <TypeID>DE94BBA4-06D1-4D40-A16A-BFD50179D6AC</TypeID>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                        <Order>5</Order>
                        <PartitionID>5</PartitionID>
                        <Format>NTFS</Format>
                        <Label>Data</Label>
                        <Letter>D</Letter>
                    </ModifyPartition>
                </ModifyPartitions>
                <DiskID>0</DiskID>
                <WillWipeDisk>true</WillWipeDisk>
            </Disk>
            <Disk wcm:action="add">
                <DiskID>1</DiskID>
                <WillWipeDisk>true</WillWipeDisk>
            </Disk>
        </DiskConfiguration>
    </component>
  </settings>
</unattend>
"@

### <ImageInstall>:
#### Same as MBR
$TemplateGPTImageInstall = $TemplateMBRImageInstall

# XML XPath:
### <DiskConfiguration>:
$TemplateDiskConfigurationXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration"
### <ImageInstall>:
$TemplateImageInstallXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/ImageInstall"

# Partition Size Array (MB):
[System.Collections.ArrayList]$PartitionSizeArray = @()

# <ImageInstall / OSImage / InstallTo / PartitionID> = "2":
$BootPartitionPartitionID = 2

#-----------------------------------------------------------[Functions]------------------------------------------------------------

# Function: Check XML node if exists by XPath
function Find-XmlNode {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlFilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlXpathwoNS
    )
    [xml]$targetXml = Get-Content $targetXmlFilePath
    # Write-Output $targetXml.OuterXml
    $targetXmlNameSpace = New-Object System.Xml.XmlNamespaceManager $targetXml.NameTable
    $targetXmlNameSpace.AddNamespace("ns", $targetXml.DocumentElement.NamespaceURI)

    $targetXmlXpath = $targetXmlXpathwoNS -replace "/", "/ns:"

    if ($targetXml.SelectSingleNode($targetXmlXpath, $targetXmlNameSpace)) {
        Write-Host "$targetXmlXpathwoNS Exists !"
        return $true
    }
    else {
        Write-Host "$targetXmlXpathwoNS DO NOT Exists !"
        return $false
    }
}

# Function: Merge XML string into XML file
function Merge-XmlFragment {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlFilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlXPathwoNS,
        [Parameter(Mandatory = $true)]
        [string]
        $sourceXMLString,
        [Parameter(Mandatory = $true)]
        [string]
        $sourceXmlXPathwoNS
    )
    [xml]$targetXml = Get-Content $targetXmlFilePath
    # Write-Output $targetXml.OuterXml
    $targetXmlNameSpace = New-Object System.Xml.XmlNamespaceManager $targetXml.NameTable
    $targetXmlNameSpace.AddNamespace("ns", $targetXml.DocumentElement.NamespaceURI)

    [xml]$sourceXml = $sourceXMLString
    $sourceXmlNameSpace = New-Object System.Xml.XmlNamespaceManager $sourceXml.NameTable
    $sourceXmlNameSpace.AddNamespace("ns", $sourceXml.DocumentElement.NamespaceURI)

    $targetXmlXpath = $targetXmlXPathwoNS -replace "/", "/ns:"
    $sourceXmlXpath = $sourceXmlXPathwoNS -replace "/", "/ns:"

    $targetXmlNode = $targetXml.SelectSingleNode($targetXmlXpath, $targetXmlNameSpace)
    $sourceXmlNode = $sourceXml.SelectSingleNode($sourceXmlXpath, $sourceXmlNameSpace)

    $targetXmlNode.AppendChild($targetXml.ImportNode($sourceXmlNode, $true)) > $null
    $targetXml.Save($targetXmlFilePath)
}

# Function: Set value to XML node
function Set-XmlNodeValue {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlFilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlXPathwoNS,
        [string]
        $valueToSet
    )
    [xml]$targetXml = Get-Content $targetXmlFilePath
    # Write-Output $targetXml.OuterXml
    $targetXmlNameSpace = New-Object System.Xml.XmlNamespaceManager $targetXml.NameTable
    $targetXmlNameSpace.AddNamespace("ns", $targetXml.DocumentElement.NamespaceURI)

    $targetXmlXpath = $targetXmlXPathwoNS -replace "/", "/ns:"

    $targetXmlNode = $targetXml.SelectSingleNode($targetXmlXpath, $targetXmlNameSpace)

    # Debug:
    Write-Host ">>>>>>>>>>>>>>>>>>>>>>"
    $targetXmlXpath
    $valueToSet
    Write-Host "<<<<<<<<<<<<<<<<<<<<<<"
    $targetXmlNode.InnerText = $valueToSet
    $targetXml.Save($targetXmlFilePath)
}

# Function: Remve XML node by XPath
# Example: Remove-XmlNode
#           -targetXmlFilePath $AnswerFileTargetPath
#           -targetXmlXPathwoNS "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[./Order=1]"
#           Node <CreatePartition> is removed.
function Remove-XmlNode {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlFilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlXpathwoNS
    )
    [xml]$targetXml = Get-Content $targetXmlFilePath
    # Write-Output $targetXml.OuterXml
    $targetXmlNameSpace = New-Object System.Xml.XmlNamespaceManager $targetXml.NameTable
    $targetXmlNameSpace.AddNamespace("ns", $targetXml.DocumentElement.NamespaceURI)

    $targetXmlXpath = $targetXmlXpathwoNS -replace "/", "/ns:"
    $targetXmlNode = $targetXml.SelectSingleNode($targetXmlXpath, $targetXmlNameSpace)

    if ($targetXmlNode) {
        $targetXmlNode.ParentNode.RemoveChild($targetXmlNode) > $null
    }
    $targetXml.Save($targetXmlFilePath)
}

# Function: Count XML node of the same name in the same level
# XPath:
# "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[./Order=$createPartitionOrder]"
# and
# "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition"
# are different.
function Get-XmlNodeCount {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlFilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlXpathwoNS
    )
    [xml]$targetXml = Get-Content $targetXmlFilePath
    # Write-Output $targetXml.OuterXml
    $targetXmlNameSpace = New-Object System.Xml.XmlNamespaceManager $targetXml.NameTable
    $targetXmlNameSpace.AddNamespace("ns", $targetXml.DocumentElement.NamespaceURI)

    $targetXmlXpath = $targetXmlXpathwoNS -replace "/", "/ns:"
    $targetXmlNode = $targetXml.SelectNodes($targetXmlXpath, $targetXmlNameSpace)

    return $targetXmlNode.Count
}

# Function: Clone a XML node at the same level
function Copy-XmlNode {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlFilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlXpathwoNS
    )

    [xml]$targetXml = Get-Content $targetXmlFilePath
    # Write-Output $targetXml.OuterXml
    $targetXmlNameSpace = New-Object System.Xml.XmlNamespaceManager $targetXml.NameTable
    $targetXmlNameSpace.AddNamespace("ns", $targetXml.DocumentElement.NamespaceURI)

    $targetXmlXpath = $targetXmlXpathwoNS -replace "/", "/ns:"
    $targetXmlNode = $targetXml.SelectNodes($targetXmlXpath, $targetXmlNameSpace)

    $targetXmlNode.ParentNode.AppendChild($targetXmlNode.Clone()) > $null
    $targetXml.Save($targetXmlFilePath)
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

# Check if Firemware Type is UEFI
if ($FirmwareType -eq 'UEFI') {
    # the firmware type is UEFI
    Write-Host "The firmware type is: UEFI" -ForegroundColor Green
    $IfFirmwareTypeUEFI = $True
}else {
    # the firmware type is Legacy
    Write-Host "The firmware type is: Legacy" -ForegroundColor Green
    $MicrosoftReservedPartitionSizeInMB = 0
    $IfFirmwareTypeUEFI = $False
}
# $IfFirmwareTypeUEFI.GetType()

# Partitions Except BootPartition
$SystemPartitionSizeInB = $SystemPartitionSizeInMB * 1024 * 1024
$MicrosoftReservedPartitionSizeInB = $MicrosoftReservedPartitionSizeInMB * 1024 * 1024
$RecoveryToolsPartitionSizeInB = $RecoveryToolsPartitionSizeInMB * 1024 * 1024
$DataPartitionSizeInB = $DataPartitionSizeInMB * 1024 * 1024

# [Boot Partition] minimum size: 40GB
$BootPartitionMinimumSizeInB = 40 * 1024 * 1024 * 1024
# [Boot Partition Disk] minimum size
$BootPartitionDiskMinimumSizeInB = $SystemPartitionSizeInB + $MicrosoftReservedPartitionSizeInB + $RecoveryToolsPartitionSizeInB + $DataPartitionSizeInB + $BootPartitionMinimumSizeInB


## Get valid $AnswerFilePath
# Check if Parameter AnswerFilePath is set
if (-not ($PSBoundParameters.ContainsKey('AnswerFilePath'))) {
    # The parameter "AnswerFilePath" is not set
    # Ask user which Answer file to be import

    # Get Thumb Drive Letters
    [System.Collections.ArrayList]$ThumbDriveLetterArray = @()
    # Get directories to check
    [System.Collections.ArrayList]$CheckFolderArray = @()
    $DriveLetters = @("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z")
    foreach ($DriveLetter in $DriveLetters) {
        $TempPath = $DriveLetter + ":\" + $DriveRootFolderName + "\"
        if (Test-Path $TempPath -PathType 'Container') {
            $ThumbDriveLetterArray.Add($DriveLetter) > $null
            $CheckFolderArray.Add($TempPath) > $null
        }
    }
    # Add script root to the checking directories
    $CheckFolderArray.Add($PSScriptRoot) > $null

    # Check the directories, and get the Answer File list
    [System.Collections.ArrayList]$AnswerFileAbsolutePathArray = @()
    if ($IfFirmwareTypeUEFI) {
        foreach ($TempPath in $CheckFolderArray) {
            # The answer file must:
            # * contain "answer"
            # * like "*xml"
            # * contain "efi" or "gpt"
            $files = Get-ChildItem $TempPath | Where-Object { $_.Name -match "answer" -and $_.Name -like "*.xml" -and ($_.Name -match "efi" -or $_.Name -match "gpt") } | Select-Object FullName
            foreach ($file in $files) {
                $AnswerFileAbsolutePathArray.Add($file) > $null
            }
        }
    }
    else {
        foreach ($TempPath in $CheckFolderArray) {
            # The answer file must:
            # * contain "answer"
            # * like "*xml"
            # * contain "bios" or "mbr"
            $files = Get-ChildItem $TempPath | Where-Object { $_.Name -match "answer" -and $_.Name -like "*.xml" -and ($_.Name -match "bios" -or $_.Name -match "mbr") } | Select-Object FullName
            foreach ($file in $files) {
                $AnswerFileAbsolutePathArray.Add($file) > $null
            }
        }
    }

    if ($AnswerFileAbsolutePathArray.Count -eq 0) {
        Write-Host "There is no answer file can by imported !"
        Write-Host "Quit..."
        exit
    }
    else {
        Write-Host "There is one or more answer files can by imported !"
        if ($AnswerFileAbsolutePathArray.Count -eq 1 -and $PSBoundParameters.ContainsKey('DriveRootFolderName')) {
            $AnswerFilePath = $AnswerFileAbsolutePathArray[0].FullName
        }else{
            # Ask user which answer file to import
            Write-Host "Please select an answer file by number:" -ForegroundColor Yellow
            foreach ($AnswerFileAbsolutePath in $AnswerFileAbsolutePathArray) {
                $index = [array]::IndexOf($AnswerFileAbsolutePathArray, $AnswerFileAbsolutePath)
                Write-Host "    " $index "-" $AnswerFileAbsolutePath.FullName -ForegroundColor Yellow
            }
            [ValidateScript( { $_ -ge 0 -and $_ -lt $AnswerFileAbsolutePathArray.Count })]
            [int]$number = Read-Host "Press the number to select an answer file"
            Write-Host "You chose:" $AnswerFileAbsolutePathArray[$number].FullName
            $AnswerFilePath = $AnswerFileAbsolutePathArray[$number].FullName
        }
    }
}
# Relative Path to Absolute Path
$AnswerFilePath = Resolve-Path -Path $AnswerFilePath
Write-Host "The source answer file path is:" $AnswerFilePath -ForegroundColor Green

# Create Folder to contain new Answer file
$AnswerFileBaseName = (Get-Item $AnswerFilePath).BaseName
$AnswerFileDirectoryName = (Get-Item $AnswerFilePath).DirectoryName
$NewContainer = $AnswerFileDirectoryName + "\" + $AnswerFileBaseName + " - " + $ScriptExecutedTime + "\"
if (-not (Test-Path $NewContainer -PathType Container)) {
    New-Item -ItemType directory -Path $NewContainer > $null
}
# Copy Answer file into new folder
$AnswerFileTargetPath = $NewContainer + "NewAnswerFile.xml"
Copy-Item $AnswerFilePath -Destination $AnswerFileTargetPath > $null
Write-Host "The target answer file path is:" $AnswerFileTargetPath -ForegroundColor Green

# Export Get-Disk Output
$GetDiskExportCsvPath = $NewContainer + "Get_Disk.csv"
Get-Disk | Export-Csv -Path $GetDiskExportCsvPath
Write-Host "Get-Disk output saved:" $GetDiskExportCsvPath -ForegroundColor Green

# Read All Disks Information
$AllDisksExceptUSB = Get-Disk | Where-Object { $_.BusType -ne "USB" } | Sort-Object -Property Size
Write-Host "All Disks (Except USB drive):"
$AllDisksExceptUSB | Format-Table  -Property FriendlyName, Number, BootFromDisk, BusType

## --------------------------------------------------

# Check if there are Hard Drives except USB Drive
$AllDisksExceptUSBCount = $AllDisksExceptUSB.Number.Count
if ($AllDisksExceptUSBCount -eq 0) {
    ### There is no Hard Drives except USB Drive
    Write-Host "Hard Drive count: No Hard Drive exists...(Except USB drive)" -ForegroundColor Red
    Write-Host "Quit..."
    exit
}

# Get valid Boot Partition Disk
$FilteredDisks = $AllDisksExceptUSB
$AllNVMeDisks = $AllDisksExceptUSB | Where-Object { $_.BusType -eq "NVMe" } | Sort-Object -Property Size
if ($AllNVMeDisks.Number.Count -gt 0) {
    # There is more than 1 NVMe disk
    if ($AllNVMeDisks[0].Size -gt $BootPartitionDiskMinimumSizeInB) {
        # The disk with the most space in the NVMe disks >= $BootPartitionDiskMinimumSizeInB
        $FilteredDisks = $AllNVMeDisks
    }
}
$BootPartitionDisk = $FilteredDisks[0]
if ($BootPartitionDisk.Size -lt $BootPartitionDiskMinimumSizeInB) {
    Write-Host "All Disks did not meet the condition (SIZE)."
    Write-Host "Quit..."
    exit
}

# Get valid $BootPartitionDiskID
$BootPartitionDiskID = $BootPartitionDisk.Number
Write-Host "The Boot Partition DiskID is: $BootPartitionDiskID" -ForegroundColor Green

# Read disk information Except Boot Partition Disk & USB Drive
$AllDisksExceptBPDnUSB = $AllDisksExceptUSB | Where-Object { $_.Number -ne $BootPartitionDiskID }
Write-Host "All Disks (Except Boot Partition Disk & USB Drive):"
$AllDisksExceptBPDnUSB | Format-Table -Property FriendlyName, Number, BootFromDisk, BusType

# Get [Boot Partition Disk] size
$BootPartitionSizeInB = $BootPartitionDisk.Size - $SystemPartitionSizeInB - $MicrosoftReservedPartitionSizeInB - $RecoveryToolsPartitionSizeInB - $DataPartitionSizeInB
$BootPartitionSizeInMB = [math]::Round($BootPartitionSizeInB / 1024 / 1024)

# Partition Size Summary:
Write-Host "Partition Size Summary:" -ForegroundColor Red
Write-Host "    System Partition Size(MB): $SystemPartitionSizeInMB" -BackgroundColor Yellow -ForegroundColor Red
Write-Host "    Microsoft Reserved Partition Size(MB): $MicrosoftReservedPartitionSizeInMB" -BackgroundColor Yellow -ForegroundColor Red
Write-Host "    Boot Partition Size(MB): $BootPartitionSizeInMB" -BackgroundColor Yellow -ForegroundColor Red
Write-Host "    Recovery Tools Partition Size(MB): $RecoveryToolsPartitionSizeInMB" -BackgroundColor Yellow -ForegroundColor Red
Write-Host "    Data Partition Size(MB): $DataPartitionSizeInMB" -BackgroundColor Yellow -ForegroundColor Red

# Modify the target Answer File:

# Check if <settings pass="windowsPE"> <component name="Microsoft-Windows-Setup"> exists:
# $SettingsComponentXPath = "/ns:unattend/ns:settings[@pass='windowsPE']/ns:component[@name='Microsoft-Windows-Setup']"
$SettingsComponentXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']"
if ($(Find-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXpathwoNS $SettingsComponentXPath)) {
    Write-Host '<settings pass="windowsPE"> <component name="Microsoft-Windows-Setup"> exists !' -ForegroundColor Green
}else {
    Write-Host '<settings pass="windowsPE"> <component name="Microsoft-Windows-Setup"> do not exists !' -ForegroundColor Green
    Write-Host "Quit..."
    exit
}

# Replace <DiskConfiguration> & <ImageInstall> with the template:
## Delete old node:
## "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration"
## "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/ImageInstall"
## Then merge new node into:
## "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']"
# Delete old node :
Remove-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXpathwoNS $TemplateDiskConfigurationXPath
Remove-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXpathwoNS $TemplateImageInstallXPath
if ($IfFirmwareTypeUEFI) {
    # UEFI
    ## Merge new node:
    Merge-XmlFragment -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $SettingsComponentXPath -sourceXmlXPathwoNS $TemplateDiskConfigurationXPath -sourceXMLString $TemplateGPTDiskConfiguration
    Merge-XmlFragment -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $SettingsComponentXPath -sourceXmlXPathwoNS $TemplateImageInstallXPath -sourceXMLString $TemplateGPTImageInstall
}else {
    # BIOS
    ## Merge new node:
    Merge-XmlFragment -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $SettingsComponentXPath -sourceXmlXPathwoNS $TemplateDiskConfigurationXPath -sourceXMLString $TemplateMBRDiskConfiguration
    Merge-XmlFragment -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $SettingsComponentXPath -sourceXmlXPathwoNS $TemplateImageInstallXPath -sourceXMLString $TemplateMBRImageInstall
}

# Collect System Partition Size:
$PartitionSizeArray.Add($SystemPartitionSizeInMB) > $null

# Collect Microsoft Reserved Partition Size:
# Get valid $BootPartitionPartitionID :
# Check if delete Microsoft Reserved Partition:
if ($IfFirmwareTypeUEFI) {
    if ($MicrosoftReservedPartitionSizeInMB -eq 0) {
        # Remove Microsoft Reserved Partition
        Write-Host "Microsoft Reserved Partition Creation: Do NOT Create..." -ForegroundColor Green
        $createPartitionOrder = "2"
        $modifyPartitionOrder = "2"
        $createPartitionXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[./Order=$createPartitionOrder]"
        $modifyPartitionXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition[./Order=$modifyPartitionOrder]"
        Remove-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $createPartitionXPath
        Remove-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $modifyPartitionXPath
    }
    else {
        # DO NOT delete Microsoft Reserved Partition
        Write-Host "Microsoft Reserved Partition Creation: Creating..." -ForegroundColor Green
        $PartitionSizeArray.Add($MicrosoftReservedPartitionSizeInMB) > $null

        # <ImageInstall / OSImage / InstallTo / PartitionID> = "3":
        $BootPartitionPartitionID = 3
    }
}

# Collect Boot Partition Size:
$PartitionSizeArray.Add($BootPartitionSizeInMB) > $null
# Collect Recovery Tools Partition Size:
$PartitionSizeArray.Add($RecoveryToolsPartitionSizeInMB) > $null

# Collect Data Partition Size:
# Check if delete Data Paritition:
if ($DataPartitionSizeInMB -eq 0) {
    Write-Host "Data Partition Creation: Do NOT Create..." -ForegroundColor Green
    # Remove Data Partition
    if ($IfFirmwareTypeUEFI) {
        $createPartitionOrder = "5"
        $modifyPartitionOrder = "5"
    }
    else {
        $createPartitionOrder = "4"
        $modifyPartitionOrder = "4"
    }
    $createPartitionXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[./Order=$createPartitionOrder]"
    $modifyPartitionXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition[./Order=$modifyPartitionOrder]"
    Remove-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $createPartitionXPath
    Remove-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $modifyPartitionXPath
}
else {
    Write-Host "Data Partition Creation: Creating..." -ForegroundColor Green
    $PartitionSizeArray.Add($DataPartitionSizeInMB) > $null
}

# Verify <CreatePartition>.Count <ModifyPartition>.Count :
$createPartitionXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition"
$modifyPartitionXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition"
if ($PartitionSizeArray.Count -ne $(Get-XmlNodeCount -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $createPartitionXPath)) {
    Write-Host 'Error: $PartitionSizeArray.Count -ne <CreatePartition>.Count' -ForegroundColor Red
    Write-Host "Quit..."
    exit
}
if ($PartitionSizeArray.Count -ne $(Get-XmlNodeCount -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $modifyPartitionXPath)) {
    Write-Host 'Error: $PartitionSizeArray.Count -ne <ModifyPartition>.Count' -ForegroundColor Red
    Write-Host "Quit..."
    exit
}

# ForEach Set <Size>, <Order>, <PartitionID>:
$tempCount = 1
foreach ($PartitionSize in $PartitionSizeArray) {
    $createPartitionPosition = $tempCount.ToString()
    $modifyPartitionPosition = $tempCount.ToString()

    # Set <Size> in <CreatePartition>:
    ## latest <CreatePartition> do not have <Size>:
    if ($tempCount -lt $PartitionSizeArray.Count) {
        $createPartitionSizeXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[position()=$createPartitionPosition]/Size"
        Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $createPartitionSizeXPath -valueToSet $PartitionSize.ToString()
    }

    # Set <Order> in <CreatePartition>:
    $createPartitionOrderXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[position()=$createPartitionPosition]/Order"
    # Set <Order> in <ModifyPartition>:
    $modifyPartitionOrderXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition[position()=$modifyPartitionPosition]/Order"
    # Set <PartitionID> in <ModifyPartition>:
    $modifyPartitionPartitionIDXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition[position()=$modifyPartitionPosition]/PartitionID"

    Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $createPartitionOrderXPath -valueToSet $tempCount.ToString()
    Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $modifyPartitionOrderXPath -valueToSet $tempCount.ToString()
    Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $modifyPartitionPartitionIDXPath -valueToSet $tempCount.ToString()

    $tempCount += 1
}

# Set <DiskConfiguration / Disk / DiskID>
# Set <ImageInstall / OSImage / InstallTo / DiskID>
# Set <ImageInstall / OSImage / InstallTo / PartitionID>
$diskConfigurationDiskDiskIDXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[position()=$createPartitionPosition]/Order"
$imageInstallOSImageInstallToDiskIDXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/ImageInstall/OSImage/InstallTo/DiskID"
$imageInstallOSImageInstallToPartitionIDXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/ImageInstall/OSImage/InstallTo/PartitionID"
# Remove <DiskConfiguration / Disk[position()=2]> if needed
$diskConfigurationSecondDiskXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=2]"
if ($AllDisksExceptUSBCount -eq 1) {
    # There is only 1 drive except USB drive:
    Write-Host "Hard Drive count: 1 (Except USB drive)"

    # Set Value:
    Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $diskConfigurationDiskDiskIDXPath -valueToSet "0"
    Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $imageInstallOSImageInstallToDiskIDXPath -valueToSet "0"
    Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $imageInstallOSImageInstallToPartitionIDXPath -valueToSet $BootPartitionPartitionID.ToString()

    # Remove Second Disk:
    Remove-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXpathwoNS $diskConfigurationSecondDiskXPath
}
else {
    # There are more than 1 drives except USB drive:
    Write-Host "Hard Drives count: $AllDisksExceptUSBCount (Except USB drive)"

    # Set Value:
    Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $diskConfigurationDiskDiskIDXPath -valueToSet $BootPartitionDiskID.ToString()
    Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $imageInstallOSImageInstallToDiskIDXPath -valueToSet $BootPartitionDiskID.ToString()
    Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $imageInstallOSImageInstallToPartitionIDXPath -valueToSet $BootPartitionPartitionID.ToString()

    $tempCount = $AllDisksExceptBPDnUSB.Number.Count
    foreach ($Disk in $AllDisksExceptBPDnUSB) {
        $tempCount = $tempCount - 1
        $order = $AllDisksExceptBPDnUSB.Number.Count - $tempCount + 1

        Write-Host "Order Number: $order (Start with '2')"
        $tempXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=$order]/DiskID"
        Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $tempXPath -valueToSet $Disk.Number.toString()

        # Clone <DiskConfiguration / Disk[position()=$order]>
        if ($tempCount -gt 0) {
            Write-Host "Cloned: <DiskConfiguration / Disk[position()=$order]>"
            $tempXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=$order]"
            Copy-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $tempXPath
        }
    }
}