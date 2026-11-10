@echo off
rem Avvia FRONTLINE DOMINION 3D (finestra di gioco, senza console).
set "GODOT=C:\Users\villa\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot 4.6.2 non trovato in:
  echo %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
