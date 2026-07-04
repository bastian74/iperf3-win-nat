@echo off
rem Launch the iperf3-nat GUI in Windows PowerShell (STA mode, required for WPF).
setlocal
set "HERE=%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%iperf3-gui.ps1"
