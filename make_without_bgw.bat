@echo Minimum version of PostgreSQL required is 9.4.0
@mkdir temp
bitsadmin.exe /transfer "Downloading BusyBox" https://frippery.org/files/busybox/busybox.exe "%~dp0temp\busybox.exe"
set EXTENSION=pg_partman
temp\busybox grep default_version %EXTENSION%.control | temp\busybox sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/" > temp\ver.txt
set /p VERSION=<temp\ver.txt
copy sql\types\*.sql + sql\tables\*.sql + sql\functions\*.sql + sql\92\tables\*.sql %EXTENSION%--%VERSION%.sql /B