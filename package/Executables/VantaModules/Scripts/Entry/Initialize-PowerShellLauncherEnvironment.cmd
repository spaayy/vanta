@echo off
rem This file is called from Vanta launchers after they have anchored themselves to
rem the protected Windows command host. Keep it free of setlocal: the sanitised
rem environment must remain in the caller before Windows PowerShell starts.
if not defined VantaWindowsRoot exit /b 1

rem __APPDIR__ identifies the running command image directory but does not attest
rem its ACL. These exact forms reject unknown hosts; callers must still start this
rem helper from the protected Windows command host rather than a copied fake tree.
set "VantaNativeSystemDirectory=%VantaWindowsRoot%\System32"
set "VantaNativeLaunchDirectory="
set "VantaNativeCommandHost=%VantaWindowsRoot%\System32\cmd.exe"
set "VantaNativePowerShell="
set "VantaNativeFltmc="
if /i "%__APPDIR__%"=="%VantaWindowsRoot%\System32\" goto vantaNativeHost
if /i "%__APPDIR__%"=="%VantaWindowsRoot%\SysWOW64\" goto vantaWow64Host
if /i "%__APPDIR__%"=="%VantaWindowsRoot%\SysArm32\" goto vantaWow64Host
exit /b 1

:vantaNativeHost
set "VantaNativeLaunchDirectory=%VantaNativeSystemDirectory%"
goto vantaHostSelected

:vantaWow64Host
rem Sysnative is only a launch alias for a WOW64 parent. The native child must
rem inherit canonical System32 values because Sysnative is absent in that child.
set "VantaNativeLaunchDirectory=%VantaWindowsRoot%\Sysnative"

:vantaHostSelected
set "VantaNativePowerShell=%VantaNativeLaunchDirectory%\WindowsPowerShell\v1.0\powershell.exe"
set "VantaNativeFltmc=%VantaNativeLaunchDirectory%\fltmc.exe"
if not exist "%VantaNativeLaunchDirectory%\cmd.exe" exit /b 1
if not exist "%VantaNativePowerShell%" exit /b 1
if not exist "%VantaNativeLaunchDirectory%\WindowsPowerShell\v1.0\Modules\" exit /b 1
set "SystemRoot=%VantaWindowsRoot%"
set "windir=%VantaWindowsRoot%"
set "ComSpec=%VantaNativeCommandHost%"
set "PATHEXT=.COM;.EXE;.BAT;.CMD"
set "PATH=%VantaNativeSystemDirectory%;%VantaWindowsRoot%;%VantaNativeSystemDirectory%\Wbem;%VantaNativeSystemDirectory%\WindowsPowerShell\v1.0"
set "COR_ENABLE_PROFILING="
set "COR_PROFILER="
set "COR_PROFILER_PATH="
set "COR_PROFILER_PATH_32="
set "COR_PROFILER_PATH_64="
set "COR_PROFILER_PATH_ARM32="
set "COR_PROFILER_PATH_ARM64="
set "COR_PROFILER_PATH_X86="
set "COR_PROFILER_PATH_AMD64="
set "CORECLR_ENABLE_PROFILING="
set "CORECLR_PROFILER="
set "CORECLR_PROFILER_PATH="
set "CORECLR_PROFILER_PATH_32="
set "CORECLR_PROFILER_PATH_64="
set "CORECLR_PROFILER_PATH_ARM64="
set "CORECLR_PROFILER_PATH_X86="
set "DOTNET_STARTUP_HOOKS="
set "DOTNET_ADDITIONAL_DEPS="
set "DOTNET_SHARED_STORE="
set "DOTNET_ROOT="
set "DOTNET_ROOT_X86="
set "DOTNET_ROOT_X64="
set "DOTNET_ROOT_ARM64="
set "DOTNET_HOST_PATH="
set "DOTNET_BUNDLE_EXTRACT_BASE_DIR="
set "APPDOMAIN_MANAGER_ASM="
set "APPDOMAIN_MANAGER_TYPE="
set "APPDOMAIN_MANAGER_APP_CONFIG="
set "APPDOMAIN_MANAGER_INITIALIZATION_OPTIONS="
set "COMPLUS_APPDOMAINMANAGERASSEMBLY="
set "COMPLUS_APPDOMAINMANAGERTYPE="
set "COMPLUS_APPLICATIONMIGRATIONRUNTIMEACTIVATIONCONFIGPATH="
set "COMPLUS_INSTALLROOT="
set "COMPLUS_VERSION="
set "COMPLUS_TPALIST="
set "COMPLUS_JITNAME="
set "COMPLUS_JITPATH="
set "COMPLUS_ALTJIT="
set "COMPLUS_ALTJITNAME="
set "COMPLUS_ALTJITPATH="
rem Keep inbox module autoload available without inheriting user-writable module roots.
set "PSModulePath=%VantaNativeSystemDirectory%\WindowsPowerShell\v1.0\Modules"
exit /b 0
