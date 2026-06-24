@echo off
setlocal

set SRC=%~dp0
rem Edit DST to your REAPER Scripts folder. Typical path:
rem   C:\Users\<you>\AppData\Roaming\REAPER\Scripts\rock-band-helpers
rem Without editing this, the script will fail with a robocopy error.
set DST=C:\Users\wejaa\AppData\Roaming\REAPER\Scripts\__new_vkr

if "%DST%"=="C:\path\to\your\REAPER\Scripts\rock-band-helpers" (
    echo ERROR: Edit the DST path in this script before running.
    pause
    exit /b 1
)

echo Deploying to %DST%
echo.

robocopy "%SRC%lib"                                     "%DST%\lib"                                      *.lua    /MIR /NJH /NJS
robocopy "%SRC%dev\tests"                               "%DST%\dev\tests"                            *.lua    /MIR /NJH /NJS
robocopy "%SRC%dev\tests\midi"                          "%DST%\dev\tests\midi"                       *.mid *.txt /MIR /NJH /NJS
robocopy "%SRC%rock_band_vocal_helper_vkr"              "%DST%\rock_band_vocal_helper_vkr"           *.lua    /MIR /NJH /NJS
robocopy "%SRC%rock_band_general_helper_vkr"            "%DST%\rock_band_general_helper_vkr"         *.lua    /MIR /NJH /NJS
robocopy "%SRC%resources\themes"                        "%DST%\resources\themes"                     *.rbtheme /MIR /NJH /NJS
robocopy "%SRC%rock_band_music_theory_helper_vkr"       "%DST%\rock_band_music_theory_helper_vkr"    *.lua    /MIR /NJH /NJS
robocopy "%SRC%dev\rock_band_venue_demo_vkr"             "%DST%\dev\rock_band_venue_demo_vkr"          *.lua    /MIR /NJH /NJS
robocopy "%SRC%resources\img"                           "%DST%\resources\img"                        *.png *.jpg /MIR /NJH /NJS
robocopy "%SRC%resources\audio\drums"                   "%DST%\resources\audio\drums"                *.ogg    /MIR /NJH /NJS
copy /Y  "%SRC%rock_band_vocal_helper_vkr.lua"          "%DST%\rock_band_vocal_helper_vkr.lua"        >nul
copy /Y  "%SRC%rock_band_general_helper_vkr.lua"        "%DST%\rock_band_general_helper_vkr.lua"      >nul
copy /Y  "%SRC%rock_band_music_theory_helper_vkr.lua"   "%DST%\rock_band_music_theory_helper_vkr.lua" >nul
copy /Y  "%SRC%dev\rock_band_venue_demo_vkr.lua"        "%DST%\dev\rock_band_venue_demo_vkr.lua"      >nul
copy /Y  "%SRC%dev\venue_sprite_tester_vkr.lua"         "%DST%\dev\venue_sprite_tester_vkr.lua"       >nul
copy /Y  "%SRC%dev\test_rock_band_helpers_vkr.lua"      "%DST%\dev\test_rock_band_helpers_vkr.lua"    >nul

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
