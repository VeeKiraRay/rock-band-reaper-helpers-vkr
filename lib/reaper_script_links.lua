-- Launcher for the other Rock Band helper scripts (shared library).
-- Backs the "General > Other tools" sub-tab of BOTH the general helper and the
-- vocal helper, so the registry and the launch mechanism exist exactly once.
--
-- Requires globals: r (reaper), ctx (ImGui context), S (status reporting),
--   Btn, BtnGroupWidth, BTN_H, SectionHeader, Tooltip
--   (lib/reaper_imgui_helpers.lua - load that first).
-- The registry and the pure helpers above the "Path resolution" section touch
-- none of those, so a Lua-only test context can dofile this file on its own.
--
-- Why a Rock Band specific registry sits in lib/: both helpers draw this same
-- tab, so it cannot live in either one's module folder without being
-- duplicated - the same reasoning that has rock_band_preview_vkr.lua reach into
-- the general helper's ui_venue_preview.lua rather than copy it.
-- lib/reaper_guitar_theory.lua is the existing precedent for RB domain
-- knowledge under a lib/reaper_*.lua name.
--
-- Why the tooltip strings are here and not in TIPS: TIPS is per-script
-- (general: defaults.lua, vocal: tips.lua), so a shared module reading TIPS
-- would need the same five strings copied into both files - guaranteed to
-- drift. Same pattern as DIRECTED_TIPS living in venue_camera.lua beside the
-- pool it describes.
--
-- TODO: rock_band_music_theory_helper_vkr is a link TARGET only - it offers no
-- reverse link back, because its ui.lua has no General tab to host this
-- sub-tab (only Drums and Guitar). Adding one means introducing a General tab
-- there first. The two standalone windows have no tab bar at all, by design.

------------------------------------------------------------------
-- Registry
--
-- Data only: no r.* or ctx use at load time. `file` is the basename at the
-- install root - every entry point deploys flat into one folder - and doubles
-- as the key that hides the running script's own button.
--
-- `short` is drawn on the button's own line, so it has to stay short enough to
-- survive beside the widest button at the default window width (560 px in the
-- general helper). `desc` is the full text, tooltip only, and may wrap over
-- several lines.
--
-- IMPORTANT: both strings may name only features a user sees WITHOUT enabling
-- "Show WIPs?" - this tab is an advert, and pointing someone at a tab that is
-- hidden by default (or worse, one known to be half-finished) is a broken
-- promise. Excluded for that reason: the general helper's Tempo Map, Drums,
-- Keys and Guitar tabs, and the vocal helper's Note Placement tab - which is
-- where its audio-driven syllable detection and Generate buttons live, so the
-- vocal entry describes the editing tabs instead. Re-check this when a tab
-- graduates out of WIP or a new one lands behind the flag.
------------------------------------------------------------------
SCRIPT_LINK_GROUPS = {
    {
        title = 'Main tools',
        entries = {
            { file  = 'rock_band_general_helper_vkr.lua',
              label = 'General Helper',
              short = 'Tab input, MIDI, difficulty, VENUE',
              desc  = 'Tab input, audio alignment,\n' ..
                      'difficulty tiers, MIDI utilities, VENUE / EVENTS authoring.' },
            { file  = 'rock_band_vocal_helper_vkr.lua',
              label = 'Vocal Helper',
              short = 'Lyrics, pitch, harmonies, validation',
              desc  = 'Lyrics and phrase markers, pitch correction and slides,\n' ..
                      'harmony parts, live tuner, phrase validation.' },
            { file  = 'rock_band_music_theory_helper_vkr.lua',
              label = 'Music Theory Helper',
              short = 'Drum and guitar reference',
              desc  = 'In-DAW reference: drum notation and patterns, guitar chord\n' ..
                      'shapes and how they map to Rock Band lanes.' },
        },
    },
    {
        title = 'Standalone windows',
        entries = {
            { file  = 'rock_band_preview_vkr.lua',
              label = 'Venue Preview',
              short = 'Venue preview in its own window',
              desc  = "The General Helper's Venue > Preview sub-tab in its own\n" ..
                      'window, so it can sit beside the generation tabs.' },
            { file  = 'rock_band_pitch_tuner_vkr.lua',
              label = 'Pitch Tuner',
              short = 'Live pitch readout in its own window',
              desc  = "The Vocal Helper's Tuner tab in its own window, so the live\n" ..
                      'readout stays visible while you work in another tab.' },
            { file  = 'rock_band_midi_pattern_vkr.lua',
              label = 'MIDI Pattern',
              short = 'Find/replace note patterns',
              desc  = "The General Helper's MIDI > Pattern sub-tab in its own\n" ..
                      'window, so it stays beside the MIDI editor while you work.' },
        },
    },
}

------------------------------------------------------------------
-- Pure helpers (global so dev/tests/script_links.lua can drive them)
------------------------------------------------------------------

-- Basename with extension, from either separator, or nil if unparseable.
function ScriptLinkBasename(path)
    if type(path) ~= 'string' then return nil end
    local base = path:match('[^/\\]+$')
    if base == '' then return nil end
    return base
end

-- Is `entry` the script currently running (so its button must be hidden)?
-- Compared case-insensitively because Windows paths are, and on a
-- case-sensitive filesystem the registry names are already the true names.
-- Whole-basename equality, never a substring match, so a stray
-- "rock_band_general_helper_vkr.lua.bak" does not hide the real entry.
function IsRunningScriptLink(entry, current_path)
    local base = ScriptLinkBasename(current_path)
    if not base then return false end
    return base:lower() == entry.file:lower()
end

-- Copy of `groups` with the running script's entry removed, and any group left
-- empty dropped (so no section header is ever drawn over nothing). Pure: takes
-- the registry and the current path explicitly, so tests can drive it without
-- being the script under test.
function FilterScriptLinkGroups(groups, current_path)
    local out = {}
    for _, g in ipairs(groups) do
        local kept = {}
        for _, e in ipairs(g.entries) do
            if not IsRunningScriptLink(e, current_path) then kept[#kept + 1] = e end
        end
        if #kept > 0 then out[#out + 1] = { title = g.title, entries = kept } end
    end
    return out
end

------------------------------------------------------------------
-- Path resolution and caches (lazy: nothing below runs at dofile time)
------------------------------------------------------------------
local _self_path, _root

-- Install root, plus the running script's own path. Resolved on first use
-- rather than at load time, so dofile'ing this file in a test runner resolves
-- nothing - the runner's own path is not an entry point and would give a bogus
-- root.
local function ScriptLinkPaths()
    if not _root then
        _self_path = ({ r.get_action_context() })[2] or ''
        _root      = _self_path:match('^(.+[\\/])') or ''
    end
    return _root, _self_path
end

-- path -> command id. AddRemoveReaScript(..., commit = true) writes
-- reaper-kb.ini, so each script is resolved once per session, not per click.
local _cmd_cache = {}

-- file -> installed?  Throttled rather than resolved per frame: it is
-- filesystem I/O in draw code. Not resolved once and frozen either -
-- deploy_to_reaper.bat is routinely run with REAPER still open.
local _exists, _exists_at = {}, nil
local EXISTS_RECHECK_S = 2.0

local function RefreshScriptLinkExistence()
    local now = r.time_precise()
    if _exists_at and (now - _exists_at) < EXISTS_RECHECK_S then return end
    _exists_at = now
    local root = ScriptLinkPaths()
    for _, g in ipairs(SCRIPT_LINK_GROUPS) do
        for _, e in ipairs(g.entries) do
            _exists[e.file] = r.file_exists(root .. e.file)
        end
    end
end

------------------------------------------------------------------
-- Launcher
------------------------------------------------------------------
-- Registers `path` as a Main-section action if it is not already, then runs it.
-- Returns the command id, or nil + a message. A third return value of true
-- means the script was already running and was NOT re-launched.
--
-- AddRemoveReaScript(add, sectionID, scriptfn, commit) returns the command id
-- (0 on failure) and is idempotent: REAPER de-duplicates by path, so re-adding
-- an already-registered file returns its existing id and creates no second
-- action. The registration is PERMANENT - the script joins the Action list,
-- which is what makes it bindable to a key or a toolbar button.
--
-- We deliberately never call AddRemoveReaScript(false, ...) afterwards:
-- removing the action would delete the user's own registration of that script
-- along with any shortcut or toolbar button bound to it, and a later re-add
-- gets a DIFFERENT command id, so the binding could not be restored.
--
-- Safe to call from inside an ImGui frame: Main_OnCommand runs a ReaScript in
-- its own Lua state, and the launched entry point only creates its context and
-- calls r.defer at top level - it draws its first frame on the next defer tick,
-- after our ImGui_End. It cannot interleave a frame with ours or touch our
-- ctx / S.
function LaunchReaScript(path)
    local cmd = _cmd_cache[path]
    if not cmd then
        cmd = r.AddRemoveReaScript(true, 0, path, true)
        if not cmd or cmd == 0 then
            return nil, 'REAPER would not register this script as an action.\n' ..
                        'Check that the file is present and readable, then try again.'
        end
        _cmd_cache[path] = cmd
    end
    -- REAPER reports toggle state 1 for a running deferred script and clears it
    -- when the defer chain ends (both helpers stop deferring when their window
    -- closes). Skipping the re-launch avoids REAPER's modal "ReaScript task
    -- control" dialog, which would block our frame. Only == 1 is trusted; 0 or
    -- -1 means "not running / unknown" and we launch as normal, so a build that
    -- does not report this behaves exactly as it would without the check.
    if r.GetToggleCommandState(cmd) == 1 then return cmd, nil, true end
    r.Main_OnCommand(cmd, 0)
    return cmd
end

------------------------------------------------------------------
-- General > Other tools sub-tab
------------------------------------------------------------------
local COL_LINK_WARNING = 0xFFAA00FF  -- warning amber, matches ui_workflow.lua / ui_midi.lua

-- Body only: the caller owns BeginTabItem / EndTabItem, the same contract as
-- DrawGeneralWorkflowTab.
function DrawGeneralLinksTab()
    RefreshScriptLinkExistence()
    local root, self_path = ScriptLinkPaths()
    local groups = FilterScriptLinkGroups(SCRIPT_LINK_GROUPS, self_path)

    r.ImGui_TextWrapped(ctx,
        'Open another tool from this set. Each one runs in its own window, ' ..
        'independently of this one. Opening a tool for the first time also adds it ' ..
        "to REAPER's Action list, so you can give it a keyboard shortcut or a " ..
        'toolbar button afterwards - it is never removed again.')
    r.ImGui_Spacing(ctx)

    -- One width across BOTH sections, so the two blocks read as a single column.
    local labels = {}
    for _, g in ipairs(groups) do
        for _, e in ipairs(g.entries) do labels[#labels + 1] = e.label end
    end
    local bw = BtnGroupWidth(labels)

    for gi, g in ipairs(groups) do
        if gi > 1 then r.ImGui_Separator(ctx) end
        SectionHeader(g.title)
        for _, e in ipairs(g.entries) do
            local present = _exists[e.file]   -- snapshot: drives the disabled pair
            if not present then r.ImGui_BeginDisabled(ctx) end
            local clicked = Btn(e.label, BTN_H, bw)
            if not present then r.ImGui_EndDisabled(ctx) end
            Tooltip(e.desc .. '\n\n' .. e.file)
            r.ImGui_SameLine(ctx)
            r.ImGui_TextDisabled(ctx, e.short)
            -- A disabled widget reports no hover, so the tooltip above is
            -- unreachable while the button is greyed out - which is why the
            -- reason is visible text. On its own line and wrapped, since it
            -- names a filename and would clip beside the button.
            if not present then
                r.ImGui_PushTextWrapPos(ctx, 0)
                r.ImGui_TextColored(ctx, COL_LINK_WARNING,
                    '! Not installed: ' .. e.file .. ' is not in the same folder as this script.')
                r.ImGui_PopTextWrapPos(ctx)
            end
            if clicked then
                local ok, err, already = LaunchReaScript(root .. e.file)
                S.last_result = nil
                if ok and already then
                    S.status = e.label .. ' is already open.'
                elseif ok then
                    S.status = 'Opened ' .. e.label .. '.'
                else
                    S.status      = 'Could not open ' .. e.label .. '.'
                    S.last_result = err .. '\n\n' .. root .. e.file
                end
            end
        end
    end
end
