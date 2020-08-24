set "diskNumber=0"

rem Create DiskPart script file
set "scriptFile=%temp%\%random%%random%%random%.tmp"
> "%scriptFile%" (
    echo SELECT DISK %diskNumber%
    echo CLEAN
    echo CONVERT MBR
    echo CREATE PARTITION PRIMARY SIZE=300
    echo FORMAT QUICK FS=NTFS LABEL="System"
    echo ASSIGN LETTER="S"
    echo ACTIVE
    echo CREATE PARTITION PRIMARY
    echo FORMAT QUICK FS=NTFS LABEL="Windows"
    echo ASSIGN LETTER="W"
)

rem execute DiskPart script file
type "%scriptFile%"
diskpart /s "%scriptFile%"

rem cleanup and exit
del /q "%scriptFile%"