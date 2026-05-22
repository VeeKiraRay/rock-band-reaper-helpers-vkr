@echo off
setlocal

set SRC=%~dp0
rem Edit DST to your REAPER Scripts folder. Typical path:
rem   C:\Users\<you>\AppData\Roaming\REAPER\Scripts\rock-band-helpers
rem Without editing this, the script will fail with a robocopy error.
set DST=C:\path\to\your\REAPER\Scripts\rock-band-helpers

if "%DST%"=="C:\path\to\your\REAPER\Scripts\rock-band-helpers" (
    echo ERROR: Edit the DST path in this script before running.
    pause
    exit /b 1
)

echo Deploying to %DST%
echo.

robocopy "%SRC%lib"                                  "%DST%\lib"                                  *.lua /MIR /NJH /NJS
robocopy "%SRC%rock_band_vocal_helper_vkr"           "%DST%\rock_band_vocal_helper_vkr"           *.lua /MIR /NJH /NJS
robocopy "%SRC%rock_band_general_helper_vkr"         "%DST%\rock_band_general_helper_vkr"         *.lua /MIR /NJH /NJS
copy /Y  "%SRC%rock_band_vocal_helper_vkr.lua"       "%DST%\rock_band_vocal_helper_vkr.lua"   >nul
copy /Y  "%SRC%rock_band_general_helper_vkr.lua"     "%DST%\rock_band_general_helper_vkr.lua" >nul

rem robocopy exit codes 0-7 are informational (success); 8+ means a real error
if %ERRORLEVEL% GTR 7 (
    echo.
    echo ERROR: copy failed. Check the paths above.
    pause
    exit /b 1
)

echo.
echo Done.
pause
