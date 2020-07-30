<#
脚本使用指南：
    1. 在U盘上创建一个文件夹"Windows_Installation"，并将所有需要的文件拷贝到该文件夹中；
    2. 应答文件的名称为：
        * BIOS: "AnswerFile_BIOS.xml"
        * UEFI: "AnswerFile_UEFI.xml"
    3. 创建两组 <Disk wcm:action="add"> </Disk>，
        * 第一组：Boot Partition 将在此硬盘上创建
            * Partition 1: System Partition
            * Partition 2: Boot Partition
            * Partition 3: Recovery Tools Partition
        * 第二组：此硬盘上仅创建一个 System Partition
    4. 将 Boot Partition 放到 第一组 <Disk wcm:action="add"> </Disk> ； <CreatePartition wcm:action="add"> </CreatePartition>，Order 为"2"

脚本基本逻辑：
    1. 确认U盘所在盘符，将其设置为变量 $ThumbDriveLetter
    2. 读取固件的类型，将其设置为变量 $FirmwareType
        * 从2个应答文件中选择一个
    3. 读取磁盘信息，为 Boot Partition 选择一个硬盘（筛选条件：BusType 为 NVMe / 空间大小 最大）
        * 将该硬盘的 DiskID 设置为变量 $BootPartitionDiskID
        * 读取该硬盘的大小，给 Boot Partition 的分区大小计算出一个合理的固定值 $BootPartitionSizeInMB
        * 记录除了U盘和该硬盘外，所有其他硬盘的 DiskID $DiskArray
        * 收集日志，将 BootFromDisk 的 DiskID 记录下来
    4. 根据 $FirmwareType 读取对应的应答文件
        * 将 $BootPartitionDiskID 设置到：Microsoft-Windows-Setup | ImageInstall | OSImage | InstallTo | DiskID / PartitionID
        * 将 $BootPartitionSizeInMB 设置到：Microsoft-Windows-Setup | DiskConfiguration | Disk[DiskID="X"] | CreatePartitions | CreatePartition[Order="X"] | Size
    5. 无论部署成功或失败，都将日志拷贝一份到U盘

TODO：
    * 日志收集
    * 将 System Partition 部署到每一个硬盘
    * UEFI应答文件
#>

## 为 System Partition 分配 300MB
$SystemPartitionSizeInB = 300 * 1024 * 1024
## 为 Recovery Tools Partition 分配 1000MB
$RecoveryToolsPartitionSizeInB = 1000 * 1024 * 1024
### 在配套使用的应答文件中，整块硬盘上，将 System Partition 和 Recovery Tools Partition 分配完后，剩余的所有空间都给 Boot Partition

## 为 Boot Partition 分配的最小值为 40GB
$BootPartitionMinSizeInB = 40 * 1024 * 1024 * 1024
### 整块硬盘的大小应该大于 $SystemPartitionSizeInB + $RecoveryToolsPartitionSizeInB + $BootPartitionMinSizeInB
### 如果 NVMe硬盘的大小 小于 上面三个变量之和，则不使用该 NVMe硬盘 作为 BootPartition
$BootPartitionDiskMinSizeInB = $SystemPartitionSizeInB + $RecoveryToolsPartitionSizeInB + $BootPartitionMinSizeInB

## 脚本开始

## 确定U盘的盘符
$ThumbDriveLetter = ''
$DriveLetters = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
foreach ($DriveLetter in $DriveLetters) {
    $TempPath = $DriveLetter + ":\Windows_Installation\"
    if (Test-Path $TempPath) {
        $ThumbDriveLetter = $DriveLetter
        break
    }
}
### 得到U盘的盘符：$ThumbDriveLetter
# Write-Host $ThumbDriveLetter

## 创建收集文件夹
$ScriptExecutedTime = Get-Date -UFormat "%Y_%m%d_%H%M%S"
$LogByCommandFolder = $ThumbDriveLetter + ":\Windows_Installation\Logs_" + $ScriptExecutedTime + "\"
if (-not (Test-Path $LogByCommandFolder -PathType Container)) {
    New-Item -ItemType directory -Path $LogByCommandFolder
}
Write-Host "Log folder created:" + $LogByCommandFolder
## 信息收集：将 Get-Disk 的输出保存到U盘
$ExportCsvPath = $LogByCommandFolder + $ScriptExecutedTime + "_Get_Disk.csv"
Get-Disk | Export-Csv -Path $ExportCsvPath

## 读取磁盘信息
## 获取除U盘以外的所有硬盘信息，并按空间大小 从大到小 的顺序进行排序：
$AllDisks = Get-Disk | Where-Object { $_.BusType -ne "USB" } | Sort-Object -Property Size
Write-Host "AllDisks(Except USB drive):"
Write-Host $AllDisks

## 确定 Boot Partition 的目标硬盘
### * BusType 为 NVMe
### * 空间大小 最大
$FilteredDisks = $AllDisks
#### 从所有 NVMe硬盘 中取空间最大的硬盘，或者从所有 非NVMe硬盘 中取空间最大的硬盘
$AllNVMeDisks = $AllDisks | Where-Object { $_.BusType -eq "NVMe" } | Sort-Object -Property Size
if ($AllNVMeDisks[0].Size -lt $BootPartitionDiskMinSizeInB) {
    ### 所有 NVMe硬盘 中空间最大的硬盘 不能达到空间大小的条件，则放弃所有NVMe硬盘
    $FilteredDisks = $AllNVMeDisks
}
elseif ($AllNVMeDisks.Length -ne 0) {
    ### 没有 NVMe硬盘
    $FilteredDisks = $AllNVMeDisks
}
#### 选择 筛选后的硬盘 中空间最大的硬盘 作为 Boot Partition
$BootPartitionDisk = $FilteredDisks[0]
if ($BootPartitionDisk.Size -lt $BootPartitionDiskMinSizeInB) {
    ### 所有 筛选后的硬盘 中空间最大的硬盘 不能达到空间大小的条件，则放弃所有硬盘，退出脚本
    Write-Host "All Disks did not meet the condition (SIZE)."
    Write-Host "Quit..."
    exit
}
#### 得到 Boot Partition所在硬盘的DiskID
$BootPartitionDiskID = $BootPartitionDisk.Number
#### 得到除了 Boot Partition所在硬盘、U盘 之外 的 所有其他硬盘
$AllDisksWOBootPartitionDisk = $AllDisks | Where-Object { $_.Number -ne $BootPartitionDiskID }
Write-Host "AllDisksWOBootPartitionDisk:"
Write-Host $AllDisksWOBootPartitionDisk

## 确定分配给 Boot Partition 的分区大小
### 扣去 System Partition 和 Recovery Tools Partition 的分区大小，得到分配给 Boot Partition 分区的大小
$BootPartitionSizeInB = $BootPartitionDisk.Size - $RecoveryToolsPartitionSizeInB - $SystemPartitionSizeInB
$BootPartitionSizeInMB = [math]::Round($BootPartitionSizeInB / 1024 / 1024)

##### >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

## 检查应答文件模板是否存在
$TemplateAnswerFile = $ThumbDriveLetter + ":\Windows_Installation\AnswerFile_BIOS.xml"
if (-not (Test-Path $TemplateAnswerFile)) {
    ### 应答文件模板不存在
    Write-Host "Answer file template not exists: " + $TemplateAnswerFile
    Write-Host "Quit..."
    exit
}


## 确定固件的类型
### 此方法仅适用于 WinPE，因此在 Windows 上执行此命令会报错。From: Check if Windows 10 is using UEFI or Legacy BIOS | Tutorials https://www.tenforums.com/tutorials/85195-check-if-windows-10-using-uefi-legacy-bios.html
$FirmwareType = '1'
$RegistryKey = 'HKLM:\System\CurrentControlSet\Control'
$FirmwareType = (Get-ItemProperty -Path $RegistryKey -Name PEFirmwareType).PEFirmwareType
#### "1": BIOS（此脚本默认为 BIOS）
#### "2": UEFI
Write-Host "FirmwareType Comfirmed: " + $FirmwareType.toString()
Write-Host "    1: BIOS"
Write-Host "    2: UEFI"

## 根据固件的类型，拷贝一份应答文件作为缓存
$AnswerFileSourcePath = $LogByCommandFolder + $ScriptExecutedTime + "_AnswerFile_Exported.xml"
if ($FirmwareType -eq '1') {
    $TemplateAnswerFile = $ThumbDriveLetter + ":\Windows_Installation\AnswerFile_BIOS.xml"
    Copy-Item $TemplateAnswerFile -Destination $AnswerFileSourcePath
}
else {
    $TemplateAnswerFile = $ThumbDriveLetter + ":\Windows_Installation\AnswerFile_UEFI.xml"
    Copy-Item $TemplateAnswerFile -Destination $AnswerFileSourcePath
}
### 得到应答文件的缓存路径：$AnswerFileSourcePath
##### <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

## 读取应答文件
[xml]$AnswerFileSourceXML = Get-Content $AnswerFileSourcePath
$AnswerFileNameSpace = New-Object System.Xml.XmlNamespaceManager $AnswerFileSourceXML.NameTable
$AnswerFileNameSpace.AddNamespace("ns", $AnswerFileSourceXML.DocumentElement.NamespaceURI)

## 处理应答文件
### 将 $BootPartitionSizeInMB 设置到：Microsoft-Windows-Setup | DiskConfiguration | Disk[DiskID="X"] | CreatePartitions | CreatePartition[Order="2"] | Size
#### 选中条件：
#### *  第一组 <Disk wcm:action="add"> </Disk> ，position() 为 "1"
#### * <CreatePartition wcm:action="add"> </CreatePartition> 的 Order 为"2"
$tempXPath = ""
$tempXPath = "/ns:unattend/ns:settings/ns:component/ns:DiskConfiguration/ns:Disk[position()=1]/ns:CreatePartitions/ns:CreatePartition[./ns:Order=2]"
$AnswerFileSourceXML.SelectSingleNode($tempXPath, $AnswerFileNameSpace).Size = $BootPartitionSizeInMB.toString()
$AnswerFileSourceXML.Save($AnswerFileSourcePath)

### 根据硬盘数量处理
#### 将下面这些元素添加到：Microsoft-Windows-Setup | DiskConfiguration
# <Disk wcm:action="add">
# <CreatePartitions>
# <CreatePartition wcm:action="add">
#     <Order>1</Order>
#     <Size>300</Size>
#     <Type>Primary</Type>
# </CreatePartition>
# </CreatePartitions>
# <ModifyPartitions>
# <ModifyPartition wcm:action="add">
#     <Active>true</Active>
#     <Format>NTFS</Format>
#     <Label>System</Label>
#     <Order>1</Order>
#     <PartitionID>1</PartitionID>
# </ModifyPartition>
# </ModifyPartitions>
# <DiskID>%DiskID%</DiskID>
# <WillWipeDisk>true</WillWipeDisk>
# </Disk>


## 获取除U盘以外的所有硬盘数量：
Write-Host "AllDisks.Count (Except USB drive):"
Write-Host $AllDisks.Number.Count.toString()
$AllDisksCount = $AllDisks.Number.Count
$tempXPath = ""
if ($AllDisksCount -eq 0) {
    ### 如果除U盘外，硬盘数量=0，则退出脚本
    Write-Host "No Hard Drive exists...(Except USB drive)"
    Write-Host "Quit..."
    exit
}
elseif ($AllDisksCount -eq 1) {
    ### 如果除U盘外，硬盘数量=1
    Write-Host "Hard Drive(s) count: 1 (Except USB drive)"
    ### 无脑将 Disk0 设置为 Boot Partition
    ### 将 "0" 设置到：Microsoft-Windows-Setup | ImageInstall | OSImage | InstallTo | DiskID
    $AnswerFileSourceXML.unattend.settings.component.ImageInstall.OSImage.InstallTo.DiskID = "0"
    ### 将 "0" 设置到：Microsoft-Windows-Setup | DiskConfiguration | Disk[DiskID="X"]
    $AnswerFileSourceXML.unattend.settings.component.DiskConfiguration.Disk[0].DiskID = "0"

    ### 基于 Position，将第二组 <Disk wcm:action="add"> </Disk> 删除
    # $tempXPath = "/ns:unattend/ns:settings/ns:component/ns:DiskConfiguration/ns:Disk[./ns:DiskID=1]"
    $tempXPath = "/ns:unattend/ns:settings/ns:component/ns:DiskConfiguration/ns:Disk[position()=2]"
    $tempNode = $AnswerFileSourceXML.SelectSingleNode($tempXPath, $AnswerFileNameSpace)
    $tempNode.ParentNode.RemoveChild($tempNode)
    $AnswerFileSourceXML.Save($AnswerFileSourcePath)
}
else {
    ### 如果除U盘外，硬盘数量>1
    Write-Host "Hard Drive(s) count: " + $AllDisksCount + " (Except USB drive)"
    ### 将 $BootPartitionDiskID 设置到：Microsoft-Windows-Setup | ImageInstall | OSImage | InstallTo | DiskID
    $AnswerFileSourceXML.unattend.settings.component.ImageInstall.OSImage.InstallTo.DiskID = $BootPartitionDiskID.toString()
    ### 将 $BootPartitionDiskID 设置到：Microsoft-Windows-Setup | DiskConfiguration | Disk[DiskID="X"]
    $AnswerFileSourceXML.unattend.settings.component.DiskConfiguration.Disk[0].DiskID = $BootPartitionDiskID.toString()

    $tempCount = $AllDisksWOBootPartitionDisk.Number.Count
    foreach ($Disk in $AllDisksWOBootPartitionDisk) {
        # $DiskID = $Disk.Number
        $tempCount = $tempCount - 1
        Write-Host "ForEach Loop:"
        Write-Host "tempCount = AllDisksWOBootPartitionDisk.Number.Count"
        Write-Host "Debug: tempCount-1 _ currentDisk.DiskID _ AllDisksWOBootPartitionDisk.Number.Count"
        Write-Host $tempCount + "_" + $Disk.Number + "_" + $AllDisksWOBootPartitionDisk.Length
        $AnswerFileSourceXML.unattend.settings.component.DiskConfiguration.Disk[$AllDisksWOBootPartitionDisk.Length - $tempCount].DiskID = $Disk.Number.toString()
        if ($tempCount -gt 0) {
            ### 将第N组 <Disk wcm:action="add"> </Disk> 克隆出一组
            $temp = $AllDisksWOBootPartitionDisk.Length - $tempCount + 1
            Write-Host $temp
            $tempXPath = "/ns:unattend/ns:settings/ns:component/ns:DiskConfiguration/ns:Disk[position()=$temp]"
            $tempNode = $AnswerFileSourceXML.SelectSingleNode($tempXPath, $AnswerFileNameSpace)
            $tempNodeCopy = $tempNode.clone()
            $tempNode.ParentNode.AppendChild($tempNodeCopy)
        }
    }
    $AnswerFileSourceXML.Save($AnswerFileSourcePath)
}



X:\Setup.exe /unattend:"$AnswerFileSourcePath"
### Windows Setup Command-Line Options | Microsoft Docs https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options

### 待收集的日志：
# $Env:WINDIR\Panther
# $Env:WINDIR\Inf\Setupapi.log
# $Env:WINDIR\System32\Sysprep\Panther
### Windows Setup Log Files and Event Logs | Microsoft Docs https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-log-files-and-event-logs