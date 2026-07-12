-- @description Vocal note create at playhead
-- @author VeeKiraRay
-- @version 1.0
-- @about
--   MIDI-editor quick action — bind to a hotkey. Creates a new vocal note at
--   the edit cursor, one MIDI-editor grid unit long, velocity 96. Pitch is
--   copied from the nearest vocal-range note (C1-C5, pitch 36-84), or C3 if
--   the take has none. The note is clamped so it never overlaps the next
--   note, and nothing is created if the cursor is inside an existing note.
--   Does nothing if no MIDI editor is open.
--
--   v1.0
--     - Initial release.

r = reaper
local _dir = ({reaper.get_action_context()})[2]:match('^(.+[\\/])')
dofile(_dir .. 'lib/vocal_note_create_core.lua')
VocalNoteCreate()
