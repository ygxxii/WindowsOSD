set "diskNumber=0"
rem Set Recovery Tools Partition Size to 500MB
set "RecoveryToolsPartitionSizeMB=500"

rem Create DiskPart script file
set "scriptFile=%temp%\%random%%random%%random%.tmp"
> "%scriptFile%" (
	echo SELECT DISK %diskNumber%
	echo CLEAN
	echo CONVERT GPT
	echo CREATE PARTITION EFI SIZE=100
	echo FORMAT QUICK FS=fat32 LABEL="System"
	echo ASSIGN LETTER="S"
	echo CREATE PARTITION MSR SIZE=32
	echo CREATE PARTITION PRIMARY
	echo FORMAT QUICK FS=ntfs LABEL="Windows"
	echo ASSIGN LETTER="W"
)

rem execute DiskPart script file
type "%scriptFile%"
diskpart /s "%scriptFile%"

rem cleanup and exit
del /q "%scriptFile%"