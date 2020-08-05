#requires -version 4
<#
.SYNOPSIS
  Modify <DiskConfiguration> settings in answer file.

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


    脚本使用指南：
        1. 自动扫描特定的文件夹：
            a. 在 硬盘/U盘 根目录下创建一个目录 "Windows_Installation"
            b. 将 源应答文件 复制到 "Windows_Installation"，并重命名，命名规则：
                * 固件为Legacy：包含 "answer"，且包含 "bios" / "mbr"，以 .xml 结尾
                * 固件为UEFI：包含 "answer"，且包含 "efi" / "gpt"，以 .xml 结尾
            c. 执行脚本
                ```
                ./XXXXX.ps1
                ```
        2. 指定 源应答文件，执行脚本：
            ```
            ./XXXXX.ps1 -AnswerFilePath "myAutounattend.xml"
            ```

    脚本处理逻辑：
        1. 确定固件类型
            * 用户使用 -FirmwareType 指定固件类型 (Legacy / UEFI)
            * 用户未使用 -FirmwareType 指定，读取当前主机的固件类型
        2. 获取 源应答文件
            * 用户使用 -AnswerFilePath 指定 源应答文件 的路径
            * 用户未使用 -AnswerFilePath 指定
                1. 扫描文件夹：
                    * 与脚本同一目录的文件夹
                    * 每个分区上的一个特定文件夹 "Windows_Installation"。这个特定文件夹的名称可以用 -DriveRootFolderName 指定
                2. 筛选出文件名符合特定规则的文件
                    * 固件为Legacy：包含 answer，且包含 bios/mbr，以 .xml 结尾
                    * 固件为UEFI：包含 answer，且包含 efi/gpt，以 .xml 结尾
                3. 弹出提示，让用户使用对应顺序的数字进行选择
                4. 如果没有扫描到与规则匹配的文件，则退出脚本
        3. 在 源应答文件 的同一目录下，创建一个新文件夹，名称为 "源应答文件的名称 + 当前执行的时间"
            * 将 源应答文件 拷贝一份到 新文件夹，"NewAnswerFile.xml"，作为【目标应答文件】
            * 将 Get-Disk 命令的输出导出到新文件夹，"Get_Disk.csv"
        4. 检查 除了U盘外，是否还有其他硬盘，如果没有则退出脚本
        5. 计算出 Boot Partition 所在硬盘所需要的最小空间，$BootPartitionDiskMinimumSizeInB
            $BootPartitionDiskMinimumSizeInB = $SystemPartitionSizeInB +                # System Partition 的大小                       使用 -SystemPartitionSizeInMB 指定
                                            $MicrosoftReservedPartitionSizeInB +        # Microsoft Reserved Partition 的大小           使用 -MicrosoftReservedPartitionSizeInMB 指定
                                            $RecoveryToolsPartitionSizeInB +            # Recovery Tools Partition 的大小               使用 -RecoveryToolsPartitionSizeInMB 指定
                                            $DataPartitionSizeInB +                     # Data Partition 的大小                         使用 -DataPartitionSizeInMB 指定
                                            $BootPartitionMinimumSizeInB                # Boot Partition 大小的最小值                   固定值 40GB
        6. 获取 Boot Partition Disk，$BootPartitionDisk
            * 用户使用 -BootPartitionDiskID 指定 Boot Partition Disk 的 DiskID
                * 读取当前主机的所有硬盘信息，如果指定的 DiskID 不存在，则退出脚本
            * 用户未使用 -BootPartitionDiskID 指定
                1. 读取当前主机的所有硬盘信息，排除掉 U盘
                2. 筛选出所有 NVMe硬盘，如果容量最大的 NVMe硬盘 < $BootPartitionDiskMinimumSizeInB，排除掉所有 NVMe硬盘；反之，则使用该硬盘作为 Boot Partition Disk
                3. 筛选出所有硬盘，如果容量最大的 硬盘 < $BootPartitionDiskMinimumSizeInB，退出当前脚本；反之，则使用该硬盘作为 Boot Partition Disk
        7. 从上面获取到 Boot Partition Disk 后，得到 Boot Partition Disk 的大小，$BootPartitionDisk.Size。可以由此计算得到 Boot Partition 的大小
            $BootPartitionSizeInB = $BootPartitionDisk.Size -
                                $SystemPartitionSizeInB -                               # System Partition 的大小
                                $MicrosoftReservedPartitionSizeInB -                    # Microsoft Reserved Partition 的大小
                                $RecoveryToolsPartitionSizeInB -                        # Recovery Tools Partition 的大小
                                $DataPartitionSizeInB                                   # Data Partition 的大小
        8. 开始修改上面拷贝的 目标应答文件，"NewAnswerFile.xml"
        9. 检查目标应答文件中，是否有 "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']"。如果没有则退出脚本
        10. 使用模板替换目标应答文件中的：
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration"
                * BIOS：使用 $TemplateMBRDiskConfiguration 替换
                * UEFI：使用 $TemplateGPTDiskConfiguration 替换
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/ImageInstall"
                * BIOS：使用 $TemplateMBRImageInstall 替换
                * UEFI：使用 $TemplateGPTImageInstall 替换
        11. 根据情况删除 目标应答文件 中创建 Microsoft Reserved Partition 的内容
            * BIOS：
                * 模板中没有此分区，不需要处理
                * $MicrosoftReservedPartitionSizeInMB 被赋值为 0
            * UEFI：
                * 如果 $MicrosoftReservedPartitionSizeInMB 为 0，删除掉对应的内容
                    * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[./Order=2]"
                    * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition[./Order=2]"
        12. 根据情况删除 目标应答文件 中创建 Data Partition 的内容
            * 如果 $DataPartitionSizeInMB 为 0，删除掉对应的内容
                * BIOS：
                    * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[./Order=4]"
                    * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition[./Order=4]"
                * UEFI：
                    * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[./Order=5]"
                    * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition[./Order=5]"
        13. 将各个分区的分区大小 $***PartitionSizeInMB 的值保存到数组 $PartitionSizeArray
            * $SystemPartitionSizeInMB                  不可能为 0
            * $MicrosoftReservedPartitionSizeInMB       可以为 0，如果为 0 则不保存到数组
            * $RecoveryToolsPartitionSizeInMB           不可能为 0
            * $DataPartitionSizeInMB                    可以为 0，如果为 0 则不保存到数组
            * $BootPartitionSizeInMB                    不可能为 0
        14. 检查数组 $PartitionSizeArray 中的元素数量 是否与以下数量相同。如果数量不相同，则退出脚本：
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions" 中的 <CreatePartition> 数量
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions" 中的 <ModifyPartition> 数量
        15. 轮询数组 $PartitionSizeArray，更新 目标应答文件 中的以下内容。设置每一个硬盘的 大小、部署顺序：
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[position()=$createPartitionPosition]/Size"
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[position()=$createPartitionPosition]/Order"
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition[position()=$modifyPartitionPosition]/Order"
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition[position()=$modifyPartitionPosition]/PartitionID"
        16. 根据 $BootPartitionDiskID 和 $BootPartitionPartitionID，更新 目标应答文件中的以下内容：
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/DiskID"
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/ImageInstall/OSImage/InstallTo/DiskID"
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/ImageInstall/OSImage/InstallTo/PartitionID"
            > 如果除了U盘外，数量 = 1 （只有 Boot Partition Disk），无脑将 DiskID 设置为 "0"
        17. 处理 目标应答文件 中的第二块硬盘：
            * "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=2]"
            > 如果除了U盘外，数量 > 1
            > 1. 克隆第二块硬盘的内容
            > 2. 将所有除了 Boot Partition Disk 之外的硬盘 的DiskID 轮询地设置到 "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=$position]/DiskID"
        18. 目标应答文件处理完成

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
# * generate a CreatePartitions.txt file for DiskPart
# * Compare measure with Select-Xml

[CmdletBinding()]
Param (
    # file path to AnswerFile
    [Parameter(Mandatory = $false)]
    [ValidateScript( { Test-Path $_ -PathType 'Leaf' })]
    [string]
    $AnswerFilePath,

    # Specify the firmware type
    [Parameter(Mandatory = $false)]
    [ValidateSet('Legacy', 'UEFI')]
    [string]
    $FirmwareType = $env:firmware_type,

    # Specify the Boot Partition Disk DiskID
    [Parameter(Mandatory = $false)]
    [int]
    $BootPartitionDiskID,

    # (EFI) System Partition size(MB, >=100MB)
    [Parameter(Mandatory = $false)]
    [ValidateScript( { $_ -ge 100 })]
    [int]
    $SystemPartitionSizeInMB = 300,

    # Microsoft Reserved Partition size(MB, =0, >=16MB, <=128MB)
    # Microsoft Reserved Partition - Wikipedia https://en.wikipedia.org/wiki/Microsoft_Reserved_Partition
    [Parameter(Mandatory = $false)]
    [ValidateScript( { $_ -eq 0 -or ($_ -ge 16 -and $_ -le 128) } )]
    [int]
    $MicrosoftReservedPartitionSizeInMB = 128,

    # Recovery Tools Partition size(MB, >=300MB)
    [Parameter(Mandatory = $false)]
    [ValidateScript( { $_ -ge 300 })]
    [int]
    $RecoveryToolsPartitionSizeInMB = 1000,

    # Data Partition size(MB, =0, >=5GB)
    [Parameter(Mandatory = $false)]
    [ValidateScript( { $_ -eq 0 -or $_ -ge 5120 } )]
    [int]
    $DataPartitionSizeInMB = 0,

    # name of the folder under drive root
    [Parameter(Mandatory = $false)]
    [string]
    $DriveRootFolderName = "Windows_Installation"
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

# Partitions Except BootPartition
$SystemPartitionSizeInB = $SystemPartitionSizeInMB * 1024 * 1024
$MicrosoftReservedPartitionSizeInB = $MicrosoftReservedPartitionSizeInMB * 1024 * 1024
$RecoveryToolsPartitionSizeInB = $RecoveryToolsPartitionSizeInMB * 1024 * 1024
$DataPartitionSizeInB = $DataPartitionSizeInMB * 1024 * 1024

# [Boot Partition] minimum size: 40GB
$BootPartitionMinimumSizeInB = 40 * 1024 * 1024 * 1024
# [Boot Partition Disk] minimum size
$BootPartitionDiskMinimumSizeInB = $SystemPartitionSizeInB + $MicrosoftReservedPartitionSizeInB + $RecoveryToolsPartitionSizeInB + $DataPartitionSizeInB + $BootPartitionMinimumSizeInB

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
        [Parameter(Mandatory = $true)]
        [string]
        $valueToSet
    )
    [xml]$targetXml = Get-Content $targetXmlFilePath
    # Write-Output $targetXml.OuterXml
    $targetXmlNameSpace = New-Object System.Xml.XmlNamespaceManager $targetXml.NameTable
    $targetXmlNameSpace.AddNamespace("ns", $targetXml.DocumentElement.NamespaceURI)

    $targetXmlXpath = $targetXmlXPathwoNS -replace "/", "/ns:"

    $targetXmlNode = $targetXml.SelectSingleNode($targetXmlXpath, $targetXmlNameSpace)

    if ($null -eq $targetXmlNode) {
        # Debug:
        Write-Host "Caution: the selected node is not exist >>>>>>>>>>>>>>>>>>>>>>" -ForegroundColor Red
        $targetXmlXpath
        $valueToSet
        Write-Host "         <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<" -ForegroundColor Red
    }
    else {
        $targetXmlNode.InnerText = $valueToSet
        $targetXml.Save($targetXmlFilePath)
    }
}

# Function: Create new Element
function New-XmlNodeElement {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlFilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $targetXmlXPathwoNS,
        [Parameter(Mandatory = $true)]
        [string]
        $elementToCreate
    )
    [xml]$targetXml = Get-Content $targetXmlFilePath
    # Write-Output $targetXml.OuterXml
    $targetXmlNameSpace = New-Object System.Xml.XmlNamespaceManager $targetXml.NameTable
    $targetXmlNameSpace.AddNamespace("ns", $targetXml.DocumentElement.NamespaceURI)

    $targetXmlXpath = $targetXmlXPathwoNS -replace "/", "/ns:"

    $targetXmlNode = $targetXml.SelectSingleNode($targetXmlXpath, $targetXmlNameSpace)

    if ($null -eq $targetXmlNode) {
        # Debug:
        Write-Host "Caution: the selected node is not exist >>>>>>>>>>>>>>>>>>>>>>" -ForegroundColor Red
        $targetXmlXpath
        $valueToSet
        Write-Host "         <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<" -ForegroundColor Red
    }
    else {
        $targetXmlNode.AppendChild($targetXml.CreateElement("$elementToCreate", $targetXml.DocumentElement.NamespaceURI)) > $null
        $targetXml.Save($targetXmlFilePath)
    }
}

# Function: Remve XML node by XPath
# Example: Remove-XmlNode \
#           -targetXmlFilePath $AnswerFileTargetPath \
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
}
else {
    # the firmware type is Legacy
    Write-Host "The firmware type is: Legacy" -ForegroundColor Green
    $MicrosoftReservedPartitionSizeInMB = 0
    $IfFirmwareTypeUEFI = $False
}
# $IfFirmwareTypeUEFI.GetType()

## Get valid $AnswerFilePath
# Check if Parameter AnswerFilePath is set
if (-not ($PSBoundParameters.ContainsKey('AnswerFilePath'))) {
    # The parameter "AnswerFilePath" is not set
    # Ask user which Answer file to be import

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
    $CheckFolderArray.Add($PSScriptRoot) > $null

    # Check the directories, and get the Answer File list
    [System.Collections.ArrayList]$AnswerFileAbsolutePathArray = @()
    if ($IfFirmwareTypeUEFI) {
        foreach ($TempPath in $CheckFolderArray) {
            # The answer file must:
            # * contain "answer"
            # * like "*.xml"
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
            # * like "*.xml"
            # * contain "bios" or "mbr"
            $files = Get-ChildItem $TempPath | Where-Object { $_.Name -match "answer" -and $_.Name -like "*.xml" -and ($_.Name -match "bios" -or $_.Name -match "mbr") } | Select-Object FullName
            foreach ($file in $files) {
                $AnswerFileAbsolutePathArray.Add($file) > $null
            }
        }
    }

    if ($AnswerFileAbsolutePathArray.Count -eq 0) {
        Write-Host "There is no answer file can by imported !" -ForegroundColor Green
        Write-Host "Quit..."
        exit
    }
    else {
        Write-Host "There is one or more answer files can by imported !"
        if ($AnswerFileAbsolutePathArray.Count -eq 1 -and $PSBoundParameters.ContainsKey('DriveRootFolderName')) {
            $AnswerFilePath = $AnswerFileAbsolutePathArray[0].FullName
        }
        else {
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
$AllDisksExceptUSB | Format-Table -Property FriendlyName, Number, BootFromDisk, BusType

## --------------------------------------------------

# Check if there are Hard Drives except USB Drive
$AllDisksExceptUSBCount = $AllDisksExceptUSB.Number.Count
if ($AllDisksExceptUSBCount -eq 0) {
    ### There is no Hard Drives except USB Drive
    Write-Host "Hard Drive count: No Hard Drive exists...(Except USB drive)" -ForegroundColor Green
    Write-Host "Quit..."
    exit
}

# Get valid Boot Partition Disk
if ($PSBoundParameters.ContainsKey('BootPartitionDiskID')) {
    # The CmdLet parameter BootPartitionDiskID is specified

    $temp = $AllDisksExceptUSB | Where-Object { $_.Number -eq $BootPartitionDiskID }
    if ($null -eq $temp) {
        Write-Host "The specified parameter BootPartitionDiskID is NOT valid." -ForegroundColor Green
        Write-Host "Quit..."
        exit
    }
    # Get Boot Partition Disk
    $BootPartitionDisk = $temp[0]
}
else {
    # The CmdLet parameter BootPartitionDiskID is NOT specified

    $FilteredDisks = $AllDisksExceptUSB
    $AllNVMeDisks = $AllDisksExceptUSB | Where-Object { $_.BusType -eq "NVMe" } | Sort-Object -Property Size
    if ($AllNVMeDisks.Number.Count -gt 0) {
        # There is more than 1 NVMe disk
        if ($AllNVMeDisks[0].Size -gt $BootPartitionDiskMinimumSizeInB) {
            # The disk with the most space in the NVMe disks >= $BootPartitionDiskMinimumSizeInB
            $FilteredDisks = $AllNVMeDisks
        }
    }
    # Get Boot Partition Disk
    $BootPartitionDisk = $FilteredDisks[0]
    if ($BootPartitionDisk.Size -lt $BootPartitionDiskMinimumSizeInB) {
        Write-Host "All Disks did not meet the condition (SIZE)." -ForegroundColor Green
        Write-Host "Quit..."
        exit
    }
    # Get $BootPartitionDiskID
    $BootPartitionDiskID = $BootPartitionDisk.Number
}



# Get [Boot Partition Disk] size
$BootPartitionSizeInB = $BootPartitionDisk.Size - $SystemPartitionSizeInB - $MicrosoftReservedPartitionSizeInB - $RecoveryToolsPartitionSizeInB - $DataPartitionSizeInB
$BootPartitionSizeInMB = [math]::Round($BootPartitionSizeInB / 1024 / 1024)

# Partition Size Summary:
Write-Host "Partition Info Summary:" -ForegroundColor Red
Write-Host "    The Boot Partition DiskID is: $BootPartitionDiskID" -ForegroundColor Green
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
}
else {
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
}
else {
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

# Verify <CreatePartition>.Count & <ModifyPartition>.Count :
$createPartitionXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition"
$modifyPartitionXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/ModifyPartitions/ModifyPartition"
if ($PartitionSizeArray.Count -ne $(Get-XmlNodeCount -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $createPartitionXPath)) {
    Write-Host 'Error: $PartitionSizeArray.Count -ne <CreatePartition>.Count' -ForegroundColor Green
    Write-Host "Quit..."
    exit
}
if ($PartitionSizeArray.Count -ne $(Get-XmlNodeCount -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $modifyPartitionXPath)) {
    Write-Host 'Error: $PartitionSizeArray.Count -ne <ModifyPartition>.Count' -ForegroundColor Green
    Write-Host "Quit..."
    exit
}

# ForEach Set <Size>, <Order>, <PartitionID>:
$tempCount = 1
foreach ($PartitionSize in $PartitionSizeArray) {
    $createPartitionPosition = $tempCount.ToString()
    $modifyPartitionPosition = $tempCount.ToString()

    # Set <Size> in <CreatePartition>:
    ## the last <CreatePartition> do not have <Size>:
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

# Remove <Size> & Add <Extend> to the last <CreatePartition>:
## Remove <Size>:
$lastCreatePartitionSizeXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[last()]/Size"
Remove-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $lastCreatePartitionSizeXPath
## Add <Extend>:
$lastCreatePartitionXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[last()]"
New-XmlNodeElement -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $lastCreatePartitionXPath -elementToCreate "Extend"
$lastCreatePartitionExtendXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/CreatePartitions/CreatePartition[last()]/Extend"
Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $lastCreatePartitionExtendXPath -valueToSet "true"

# Set <DiskConfiguration / Disk / DiskID>
# Set <ImageInstall / OSImage / InstallTo / DiskID>
# Set <ImageInstall / OSImage / InstallTo / PartitionID>
$diskConfigurationDiskDiskIDXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=1]/DiskID"
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

    # Read disk information Except Boot Partition Disk & USB Drive
    $AllDisksExceptBPDnUSB = $AllDisksExceptUSB | Where-Object { $_.Number -ne $BootPartitionDiskID }
    Write-Host "All Disks (Except Boot Partition Disk & USB Drive):"
    $AllDisksExceptBPDnUSB | Format-Table -Property FriendlyName, Number, BootFromDisk, BusType

    $tempCount = $AllDisksExceptBPDnUSB.Number.Count
    foreach ($Disk in $AllDisksExceptBPDnUSB) {
        $tempCount = $tempCount - 1
        $position = $AllDisksExceptBPDnUSB.Number.Count - $tempCount + 1

        Write-Host "Position Number: $position (Start with '2')"
        $tempXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=$position]/DiskID"
        Set-XmlNodeValue -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $tempXPath -valueToSet $Disk.Number.toString()

        # Clone <DiskConfiguration / Disk[position()=$position]>
        if ($tempCount -gt 0) {
            Write-Host "Cloned: <DiskConfiguration / Disk[position()=$position]>"
            $tempXPath = "/unattend/settings[@pass='windowsPE']/component[@name='Microsoft-Windows-Setup']/DiskConfiguration/Disk[position()=$position]"
            Copy-XmlNode -targetXmlFilePath $AnswerFileTargetPath -targetXmlXPathwoNS $tempXPath
        }
    }
}

# X:\Setup.exe /unattend:"$AnswerFileTargetPath"
