@echo off
rem Starts the game on DirectX 12 (the default) with a console showing its log.
rem Use it when the game closes on its own: the last lines say why.
"%~dp0Delegate.console.exe" --rendering-driver d3d12
pause
