wpeinit
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
@for %%a in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do @if exist %%a:\Windows_Installation\ set THUMBDRIVE=%%a
@echo The Images folder is on drive: %THUMBDRIVE%
Powershell.exe -Executionpolicy bypass -Nologo -Noprofile -File %THUMBDRIVE%:\Windows_Installation\PowerShell_Launch.ps1