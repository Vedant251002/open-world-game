@echo off
rem Safe mode: the simpler OpenGL renderer, for graphics drivers that
rem crash on DirectX 12 and Vulkan. Looks plainer, runs almost anywhere.
start "" "%~dp0Delegate.exe" --rendering-method gl_compatibility
