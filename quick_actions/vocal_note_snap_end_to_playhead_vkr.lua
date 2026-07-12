-- @description Vocal note snap end to playhead
-- @author VeeKiraRay
-- @version 1.0
-- @about
--   MIDI-editor quick action — bind to a hotkey. Finds the vocal-range note
--   (C1-C5, pitch 36-84) on the edit cursor, or the nearest one starting
--   before the cursor within 1 s, selects it, and stretches it so it ends at
--   the cursor. Notes starting at or after the cursor are ignored (the end
--   cannot land before the start). Does nothing if no MIDI editor is open or
--   no note is in range.
--
--   v1.0
--     - Initial release.

r = reaper
local _dir = ({reaper.get_action_context()})[2]:match('^(.+[\\/])')
dofile(_dir .. 'lib/vocal_note_snap_core.lua')
VocalNoteSnap('end')
