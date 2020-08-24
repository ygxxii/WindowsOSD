set "diskNumber=0"

rem Create DiskPart script file
set "scriptFile=%temp%\%random%%random%%random%.tmp"
> "%scriptFile%" (
    echo SELECT DISK %diskNumber%
    echo CLEAN
    echo CONVERT MBR
    echo CREATE PARTITION PRIMARY
    echo FORMAT QUICK FS=NTFS LABEL="SystemNWindows"
    echo ACTIVE
    echo ASSIGN LETTER="S"
)

rem execute DiskPart script file
type "%scriptFile%"
diskpart /s "%scriptFile%"

rem cleanup and exit
del /q "%scriptFile%"