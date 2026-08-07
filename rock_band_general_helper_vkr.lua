-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.46
-- @about
--   Utility actions for Rock Band authoring in REAPER.
--
--   Tabs:
--     General    - audio alignment, count-in positioning, song fade out, settings,
--                  per-project authoring workflow checklist
--     Tempo Map  - audio-driven tempo map generation from drum stems
--     Drums      - convert GM MIDI to Rock Band 5-lane drum notation
--     Keys       - hand split, Pro Keys conversion + animation, 5-Lane Keys conversion
--     Guitar     - convert raw MIDI to Expert Guitar gems, tab guide, validate
--     Difficulty - copy and validate Pro Keys + Keys + Guitar/Bass + Drums difficulty tiers
--     Tab Input  - guitar/keys/vocal tab entry guide
--     MIDI       - MIDI alignment, length sync, pattern replace
--     Venue      - list, validate, and generate VENUE and EVENTS track events
--
--   Built with Claude (Anthropic) - https://claude.ai
--
--   This @about block keeps only the 5 most recent versions.
--   Full history: CHANGELOG.md in the repo.
--
--   v0.9.46
--     - Tab Input > Guitar / Bass: the guide no longer truncates a chord
--       before classifying it, so it now agrees with the Music Theory
--       helper's Shape Search on every shape. Both tools answer the same
--       question - how a chord maps to RB - and Shape Search was the one
--       getting it right. The guide had been reducing each chord to 3
--       PHYSICAL notes by array position (lowest, middle, highest) before
--       any harmonic analysis, which could throw away the root and keep a
--       doubled note: an open D (2 3 2 0 0 -) lost every D and was reported
--       as a 1-3 chord instead of a 3-note major triad, and a C/G
--       (0 1 0 2 3 3) lost both C's the same way. Worse, "3 3 0 0 x 3"
--       became three octaves of G - one pitch class, no suggestable width -
--       and was charted as a 3-note chord, while the identical G5 voiced as
--       "- - 0 0 x 3" was correctly a 1-3 power chord. Nothing needed
--       reducing in the first place: the tab writes nothing to the project,
--       and the gem count already comes from distinct PITCH CLASSES across
--       the whole shape (2 for a dyad, 3 for a real triad).
--     - Tab Input > Guitar / Bass: the guide no longer reads Max chord,
--       Allow 1-4, or Phrase gap. Those sliders belong to the Guitar tab's
--       converter and are only visible when WIP tabs are enabled, but they
--       were steering this tab's output even though it does not offer them.
--       An octave dyad now correctly reports 1-4, and phrase breaks come
--       from blank lines in the tab, as documented. The Guitar tab
--       converter is unaffected - it keeps its own settings and its gem
--       assignments are unchanged.
--     - Chord names: a chord voiced with a doubled note now reports its
--       interval name instead of "Unrecognized chord shape". A power chord
--       was the only such shape that had a name, so an octave-doubled sixth
--       or third came back unnamed from the classifier while the RB mapping
--       happily called it a 1-3 dyad. Affects the chord name shown in both
--       the Tab Input report and Music Theory > Shape Search.
--   v0.9.45
--     - Venue > Actions: new "Validate" section with a "Validate
--       lighting/blends" button - a read-only audit of the lighting and post
--       proc authoring on the VENUE track, checking the same two rules the
--       generators write from, read back off the track.
--       [first] keyframes: every manual lighting event that CHANGES the
--       running preset needs one on its exact tick. A [first] anywhere else
--       is reported with what to do about it - move it (it is within a beat
--       of a change that is missing one, so fixing the first list cannot
--       leave a duplicate behind), or delete it (on a blend anchor, on an
--       automatic preset that takes no keyframes, on a tick with no lighting
--       event, or a second copy). An event restating the preset already
--       running is correctly [first]-free and is never flagged for lacking
--       one, matching the v0.9.43 rule.
--       Blends: a preset change fades only when the OUTGOING preset is
--       restated shortly before it. Changes with no such anchor are listed
--       for lighting and post proc independently, each naming the outgoing
--       preset and where it started. A hard cut is valid, so the report says
--       so - the list is "where a fade would need an anchor", not "where the
--       track is wrong".
--       Always reads the whole track (judging a change, or an anchor, needs
--       the events before it); with a time selection active only issues
--       inside it are reported. New actions_venue_validate.lua, whose
--       ValidateVenueLightingBlends is pure over three sorted event arrays -
--       covered by a new Venue Validate test set with no project fixture.
--     - Internal: the "two identical adjacent events are a blend anchor" test
--       is now one shared IsBlendAnchor (venue_lighting.lua). Three features
--       read it back off a track and have to agree - Manual gen's Blend
--       button refusing a third copy, the new validator, and the keyframe
--       restatement rule - and it had been an inline comparison in each.
--       Also added actions_venue_subtracks.lua to the entry point's
--       missing-file check, which had only ever listed it for loading.
--   v0.9.44
--     - Venue: expanded directed-camera dropdown labels whose abbreviation
--       could be read as something else. "lt" is "long time", not "lighting":
--       [directed_all_lt] is now "All (Long time)" and [directed_drums_lt]
--       "Drums (Long time)". "cls" close-ups now say "Close-up" rather than
--       "Close" (vocals, bass, guitar), the [directed_bre] / [directed_brej]
--       cuts spell out "Big Rock Ending", and the cam_pr / cam_pt pair -
--       previously the opaque "(Camera PR)" / "(Camera PT)" - now name what
--       actually differs between them: "Vocals (Long pre-roll)" / "Vocals
--       (Long post-roll)", same for guitar. Labels only; the event text
--       written to the VENUE track is unchanged, as are saved settings
--       (both store the bare event name).
--     - Venue > Manual gen: the "Normal camera" dropdown got the same
--       treatment - it listed raw event names before. The coop_ prefix is
--       dropped (it is on every entry, so it distinguishes nothing), the
--       one-letter instrument codes are spelled out, and a two-letter code
--       reads as a duo: [coop_all_far] is "All (Far)", [coop_d_near] is
--       "Drums (Near)", [coop_dv_near] is "Duo Drums/Vocals (Near)". The
--       close-ups drop the redundant word - [coop_g_closeup_hand] is
--       "Guitar (Hands)", [coop_g_closeup_head] "Guitar (Head)" - since
--       there is no non-close-up hand or head shot. Hover sprites still
--       key off the raw name, and the Preview sub-tab still shows the
--       literal event text, so cross-checking against the MIDI is
--       unaffected. New COOP_LABELS (venue_camera.lua), covered along
--       with DIRECTED_LABELS by a new Venue Labels test.
--     - Venue: every camera / lighting / post proc tooltip in Manual gen
--       and Section gen now ends with the exact event text that will be
--       written - [coop_all_far], [lighting (verse)], [ProFilm_a.pp] -
--       dimmed under a separator, so a friendly label never hides the
--       raw name. Normal camera, which showed only a sprite, now has
--       that line as its first text. The 14 tooltips were all
--       hand-rolled Begin/Draw/Text/End blocks and are now one shared
--       VenueEventTooltip (venue_sprites.lua), which also settles a
--       small inconsistency - the directed preview drew a separator
--       before its description, lighting and post proc did not. Manual
--       gen's Add buttons build their event text with the same new
--       RawVenueEventText the tooltip uses, so what you hover and what
--       lands on the VENUE track cannot drift apart.
--     - Venue: the option lists are now ordered alphabetically by label
--       instead of the order they happened to be authored in. Normal
--       camera is grouped Venue / Solo / Duo (the same buckets the
--       generator uses), Lighting stays split into Manual (needs
--       keyframes) / Automatic since only the manual presets take
--       keyframes, and each group is A-Z within itself. The two Big
--       Rock Ending cuts sit last in Directed camera, after a separator,
--       rather than between the everyday cuts. Post proc was already
--       alphabetical by event name; it now follows the labels, which
--       moves "Sucky TV" ([shitty_tv.pp]) after "Space Woosh". Display
--       order only - the event pools keep their authored order, so
--       generated results, saved section configs and the spritesheet
--       tooling are all unaffected. New shared SortedByLabel /
--       ComboGroupHeader (lib/reaper_imgui_helpers.lua).
--   v0.9.43
--     - Venue: corrected what lightpreset_blendin / postproc_blendin mean.
--       They were implemented as "place THIS section's lighting/postproc
--       event N beats before the section start", which blends nothing - it
--       just moves the hard cut earlier, and makes the new section's preset
--       run over the last N beats of the previous section. RB3 changes
--       preset when the section begins either way; the blendin value says
--       how many beats ahead of that boundary the PREVIOUSLY active preset
--       is re-stated, giving the game an anchor to interpolate from. A
--       section's own events now always sit on its section start, and the
--       outgoing preset is duplicated ahead of it instead:
--         m3     [lighting (stomp)]  [ProFilm_a.pp]
--         m9 b3  [ProFilm_a.pp]                     (postproc_blendin 2)
--         m9 b4  [lighting (stomp)]  [first]        (lightpreset_blendin 1)
--         m10    [lighting (verse)]  [ProFilm_b.pp]  [first]
--       This changes what every shipped theme produces - they all set
--       blendin. blendin 0 / absent still means a hard cut at the section
--       start, so the snap behaviour is unchanged and still reachable.
--       A duplicate is skipped when the preset is not actually changing
--       (lighting and postproc judged independently) or when it would land
--       at or before the event it copies. New BlendPpq /
--       EmitBlendDuplicates and a two-pass ResolveThemeSection /
--       EmitThemeSection split of the old ProcessThemeSection
--       (venue_lighting.lua) - emitting a section needs the previous
--       section's picks, which isn't visible one section at a time.
--       Section gen, which only ever sees one section, reads the outgoing
--       preset off the VENUE track (new FindActiveVenuePresetsBefore,
--       venue_generator.lua) and no longer clears back over those events.
--     - Venue > Manual gen: new "Blend" button beside "Add" on the Lighting
--       and Post proc rows. It copies the preset of that type currently
--       running to the playhead - the same blend anchor Themes gen and
--       Section gen place from lightpreset_blendin / postproc_blendin - so
--       a hand-authored transition fades instead of cutting. Park the
--       playhead a beat or two before the boundary, click Blend, then add
--       the new preset at the boundary itself. It reads the VENUE track
--       rather than the dropdown above, so it copies whatever is actually
--       playing, and reports the event it copied with the position it came
--       from. Refused, with a report naming what it found and where, when
--       the last two events of that type already match (a blend is already
--       in place), when one is already on the playhead, or when none
--       precedes it; a refusal creates no undo point. New
--       ResolveBlendSource (pure, so the rule is testable without a
--       playhead) and BlendVenuePresetAtPlayhead, actions_venue_manual.lua.
--     - Venue: [first] now marks a preset CHANGE. A lighting event that
--       restates the preset already running - a blend duplicate, or a
--       section that kept the previous section's preset - no longer
--       restarts the keyframe sequence; the train from the event that did
--       start it simply carries on through. This is what lets the
--       Keyframes tab agree with the generators: it can't see sections or
--       blendin values, only the events on the track, so "regenerate"
--       would otherwise put a [first] back on every blend duplicate.
--       Enforced in three places from the same rule - the section emitter
--       (venue_lighting.lua), RegenerateVenueKeyframes' span walk, which
--       now neither starts nor ends a span on an event repeating the one
--       immediately before it, and Manual gen's span-end clamp, which no
--       longer lets a duplicate of the preset being keyframed cut the
--       train short. Only ADJACENT events are compared, so two sections
--       sharing a preset with a different one between them are each still
--       a real change.
--   v0.9.42
--     - Venue: [first] keyframes now land on the SAME tick as the manual
--       lighting event they drive - [first] is that event's own initial
--       keyframe, not a later "start reacting here" marker. Themes gen and
--       Section gen were the worst offenders: they place the lighting event
--       lightpreset_blendin beats BEFORE the section start (1-4 beats in
--       nearly every shipped theme) but put [first] on the section start, so
--       it was routinely beats late. The section start now carries the first
--       [next] instead, leaving the rest of the keyframe train exactly where
--       it was. Keyframes tab and Manual gen were already anchored on the
--       lighting event except in "Closest beat" mode, where [first] was
--       snapped off it - that snapped beat is now a [next] too.
--       Instrument-aware align modes are the one exception: they add no
--       [next] at the section start, since every [next] there must be backed
--       by a real note.
--     - Venue > Manual gen: inserting a bare [first], and the whole keyframe
--       row (align, subdivision, rate, Add), are now blocked unless the
--       playhead sits on a manual lighting event - hovering the "(blocked)"
--       marker explains why, as the Events tab already did. The keyframe row
--       is gated on the event actually under the playhead rather than the
--       Lighting dropdown, so an existing [lighting (stomp)] can be
--       re-keyframed without re-picking it.
--     - Venue: keyframe align mode 0 renamed to "Keyframe rate only" (was
--       "Section start", and "Playhead" in Manual gen - two label lists that
--       had drifted apart, now one shared KF_ALIGN_LABELS). No align mode
--       decides where [first] goes any more; they only choose where the
--       first [next] lands, and the tooltips now say so. Mode indices are
--       unchanged, so saved settings still load.
--     - Internal: Manual gen's keyframe generation was a verbatim copy of
--       GenerateKeyframesForSpan's body - it now calls it, so the two can no
--       longer drift. New shared SnapPpqToHalfBeat (venue_lighting.lua)
--       replaces the half-beat snap duplicated in venue_generator.lua and
--       actions_venue_section.lua.
r = reaper  -- global so all dofile'd modules can use it

if not r.ImGui_CreateContext then
    r.ShowMessageBox(
        "This script requires the ReaImGui extension.\n\n" ..
        "Install it via Extensions > ReaPack > Browse packages,\n" ..
        "then search for 'ReaImGui' and install it.",
        "Missing dependency", 0
    )
    return
end

if not r.ImGui_BeginDisabled then
    r.ShowMessageBox(
        "This script requires ReaImGui 0.7 or later.\n\n" ..
        "Update it via Extensions > ReaPack > Browse packages,\n" ..
        "then search for 'ReaImGui' and update.",
        "ReaImGui version too old", 0
    )
    return
end

ctx = r.ImGui_CreateContext('Rock Band General Helper')  -- global

-- Module files live in a subfolder named after this script (without .lua).
-- Renaming the entry point requires renaming the folder too - intentional.
local _script  = ({reaper.get_action_context()})[2]
local _dir     = _script:match('^(.+[\\/])')
local _mdir    = _dir .. _script:match('[/\\]([^/\\]+)%.lua$') .. '/'
SCRIPT_MDIR    = _mdir  -- global: module files need this for filesystem paths
SCRIPT_DIR     = _dir   -- global: repo root; used for resources/ paths (e.g. themes, spritesheets)

for _, _f in ipairs({
    _dir  .. 'lib/reaper_imgui_helpers.lua',
    _dir  .. 'lib/reaper_dsp.lua',
    _dir  .. 'lib/reaper_midi_helpers.lua',
    _dir  .. 'lib/reaper_guitar_theory.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'settings.lua',
    _mdir .. 'helpers.lua',
    _mdir .. 'venue.lua',
    _mdir .. 'venue_awareness.lua',
    _mdir .. 'section_events.lua',
    _mdir .. 'venue_themes.lua',
    _mdir .. 'venue_camera.lua',
    _mdir .. 'venue_sprites.lua',
    _mdir .. 'venue_lighting.lua',
    _mdir .. 'venue_generator.lua',
    _mdir .. 'actions_venue_section.lua',
    _mdir .. 'actions_venue_manual.lua',
    _mdir .. 'actions_venue_events.lua',
    _mdir .. 'actions_venue_keyframes.lua',
    _mdir .. 'actions_venue_sing_along.lua',
    _mdir .. 'actions_venue_subtracks.lua',
    _mdir .. 'actions_venue_validate.lua',
    _mdir .. 'workflow.lua',
    _mdir .. 'actions_workflow.lua',
    _mdir .. 'tempomap.lua',
    _mdir .. 'actions.lua',
    _mdir .. 'actions_tempomap.lua',
    _mdir .. 'actions_drums.lua',
    _mdir .. 'actions_keys.lua',
    _mdir .. 'actions_keys_guides.lua',
    _mdir .. 'actions_guitar.lua',
    _mdir .. 'actions_guitar_guide.lua',
    _mdir .. 'actions_guitar_validate.lua',
    _mdir .. 'actions_midi_align.lua',
    _mdir .. 'actions_midi_replace.lua',
    _mdir .. 'actions_midi_length.lua',
    _mdir .. 'actions_difficulty_shared.lua',
    _mdir .. 'actions_difficulty.lua',
    _mdir .. 'actions_difficulty_5k.lua',
    _mdir .. 'actions_difficulty_gtrbass.lua',
    _mdir .. 'actions_difficulty_drums.lua',
    _mdir .. 'ui_keys.lua',
    _mdir .. 'ui_difficulty.lua',
    _mdir .. 'ui_midi.lua',
    _mdir .. 'ui_venue.lua',
    _mdir .. 'ui_venue_section_gen.lua',
    _mdir .. 'ui_venue_manual.lua',
    _mdir .. 'ui_venue_events.lua',
    _mdir .. 'ui_venue_preview.lua',
    _mdir .. 'ui_venue_keyframes.lua',
    _mdir .. 'ui_venue_players.lua',
    _mdir .. 'ui_workflow.lua',
    _mdir .. 'ui.lua',
}) do
    if not r.file_exists(_f) then
        r.ShowMessageBox(
            'A required file is missing:\n\n  ' .. _f:sub(#_dir + 1) ..
            '\n\nPlease reinstall the script.',
            'Missing file', 0)
        return
    end
end

dofile(_dir  .. 'lib/reaper_imgui_helpers.lua')
dofile(_dir  .. 'lib/reaper_dsp.lua')
dofile(_dir  .. 'lib/reaper_midi_helpers.lua')
dofile(_dir  .. 'lib/reaper_guitar_theory.lua')
dofile(_mdir .. 'defaults.lua')
dofile(_mdir .. 'settings.lua')
dofile(_mdir .. 'helpers.lua')
dofile(_mdir .. 'venue.lua')
dofile(_mdir .. 'venue_awareness.lua')
dofile(_mdir .. 'section_events.lua')
dofile(_mdir .. 'venue_themes.lua')
dofile(_mdir .. 'venue_camera.lua')
dofile(_mdir .. 'venue_sprites.lua')
dofile(_mdir .. 'venue_lighting.lua')
dofile(_mdir .. 'venue_generator.lua')
dofile(_mdir .. 'actions_venue_section.lua')
dofile(_mdir .. 'actions_venue_manual.lua')
dofile(_mdir .. 'actions_venue_events.lua')
dofile(_mdir .. 'actions_venue_keyframes.lua')
dofile(_mdir .. 'actions_venue_sing_along.lua')
dofile(_mdir .. 'actions_venue_subtracks.lua')
dofile(_mdir .. 'actions_venue_validate.lua')
dofile(_mdir .. 'workflow.lua')
dofile(_mdir .. 'actions_workflow.lua')
dofile(_mdir .. 'tempomap.lua')
dofile(_mdir .. 'actions.lua')
dofile(_mdir .. 'actions_tempomap.lua')
dofile(_mdir .. 'actions_drums.lua')
dofile(_mdir .. 'actions_keys.lua')
dofile(_mdir .. 'actions_keys_guides.lua')
dofile(_mdir .. 'actions_guitar.lua')
dofile(_mdir .. 'actions_guitar_guide.lua')
dofile(_mdir .. 'actions_guitar_validate.lua')
dofile(_mdir .. 'actions_midi_align.lua')
dofile(_mdir .. 'actions_midi_replace.lua')
dofile(_mdir .. 'actions_midi_length.lua')
dofile(_mdir .. 'actions_difficulty_shared.lua')
dofile(_mdir .. 'actions_difficulty.lua')
dofile(_mdir .. 'actions_difficulty_5k.lua')
dofile(_mdir .. 'actions_difficulty_gtrbass.lua')
dofile(_mdir .. 'actions_difficulty_drums.lua')
dofile(_mdir .. 'ui_keys.lua')
dofile(_mdir .. 'ui_difficulty.lua')
dofile(_mdir .. 'ui_midi.lua')
dofile(_mdir .. 'ui_venue.lua')
dofile(_mdir .. 'ui_venue_section_gen.lua')
dofile(_mdir .. 'ui_venue_manual.lua')
dofile(_mdir .. 'ui_venue_events.lua')
dofile(_mdir .. 'ui_venue_preview.lua')
dofile(_mdir .. 'ui_venue_keyframes.lua')
dofile(_mdir .. 'ui_venue_players.lua')
dofile(_mdir .. 'ui_workflow.lua')
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end

-- Startup initialisation (runs after all modules are loaded)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultTempoTracks()
SetDefaultMIDITracks()
SetDefaultDifficultyTracks()
