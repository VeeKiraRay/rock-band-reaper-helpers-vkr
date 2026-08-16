-- songs.dta parsing for the calibration corpus.
--
-- PURE: takes the file's text, returns a table per song entry. No r.*, no S,
-- no file I/O, so dev/tests can drive it with literal strings and the corpus
-- walker can drive it with real files.
--
-- Status: calibration pilot, dev-only. See
-- _future_ideas/general_difficulty_suggester.md -> "Calibration corpus".
--
-- ---------------------------------------------------------------------------
-- What the real files taught us (all of this is load-bearing, not defensive):
--
--  * A pack holds 1..N entries. 103 of the corpus's 155 songs live in 12
--    multi-song packs, so a parser that reads only the first entry silently
--    drops two thirds of the data.
--  * Entries begin at column 0 with "(<shortname>"; nothing else in these
--    files starts at column 0.
--  * Rank parsing MUST be scoped to inside the (rank ...) block. One dta
--    writes a single-channel track as "(bass 5)" inside (tracks), which a
--    whole-file match reads as a rank of 5.
--  * (game_origin ...) appears AFTER the rank block, so origin cannot be
--    resolved in the same forward pass that reads a rank - callers get it on
--    the finished entry, which is why this returns records rather than
--    streaming.
--  * Rank keys can be absent entirely, not just zero. The Green Day export
--    carries no keys/real_* lines at all. Absent and 0 both mean "no part".
--  * Indentation and the set of optional fields vary between files, so
--    nothing may key off line position or exact spacing.
-- ---------------------------------------------------------------------------

-- Rank keys as they actually appear. Note "drum" is singular, and "real_*" is
-- the pro variant of each instrument.
DTA_RANK_KEYS = {
    'drum', 'guitar', 'bass', 'vocals', 'keys',
    'real_guitar', 'real_bass', 'real_keys', 'band',
}

----------------------------------------------------------------------

local function NewEntry(shortname)
    return {
        shortname   = shortname,
        origin      = nil,
        genre       = nil,
        sub_genre   = nil,
        vocal_parts = nil,   -- missing on 2 corpus songs that do have a vocals rank
        ranks       = {},    -- only keys actually present, values > 0 kept as-is
    }
end

-- text: the whole contents of one songs.dta.
-- Returns an array of entry records in file order.
function ParseSongsDta(text)
    local entries = {}
    local cur     = nil
    local in_rank = false

    for line in (text .. '\n'):gmatch('([^\r\n]*)\r?\n') do
        local sn = line:match('^%(([%w_]+)')
        if sn then
            cur     = NewEntry(sn)
            in_rank = false
            entries[#entries + 1] = cur
        elseif cur then
            if in_rank then
                -- A bare ")" on its own line closes the rank block.
                if line:match('^%s*%)%s*$') then
                    in_rank = false
                else
                    local k, v = line:match('%(([%a_]+)%s+(%d+)%)')
                    if k and v then cur.ranks[k] = tonumber(v) end
                end
            elseif line:match('%(rank') then
                in_rank = true
                -- Tolerate a value sharing the (rank line, though no corpus
                -- file does this today.
                local k, v = line:match('%(rank%s+%(([%a_]+)%s+(%d+)%)')
                if k and v then cur.ranks[k] = tonumber(v) end
            else
                local origin = line:match('%(game_origin%s+([%w_]+)%)')
                if origin then cur.origin = origin end
                -- Skip commented-out lines before reading genre/sub_genre. Every Magma
                -- template pack carries 26 copies of ";;(sub_genre ^^^garage^^^)", and
                -- one pack has a real ";;(sub_genre psychedelicrock)" - read literally,
                -- those placeholders would make `garage` the corpus's commonest
                -- subgenre. Only these two fields need the guard: they are the only ones
                -- that appear commented out anywhere in the corpus.
                local uncommented = line:match('^%s*;;') and '' or line
                local genre = uncommented:match('%(genre%s+([%w_]+)%)')
                if genre then cur.genre = genre end
                local sub = uncommented:match('%(sub_genre%s+([%w_]+)%)')
                if sub then cur.sub_genre = sub end
                local vp = line:match('%(vocal_parts%s+(%d+)%)')
                if vp then cur.vocal_parts = tonumber(vp) end
            end
        end
    end

    return entries
end

-- Rank for one instrument, or nil when the song has no such part.
-- Absent key and 0 are the same answer: verified against the corpus, a zero
-- rank always means the MIDI has no such track.
function DtaRank(entry, inst)
    local v = entry.ranks[inst]
    if not v or v <= 0 then return nil end
    return v
end

-- Path of a song's MIDI relative to its pack root.
--
-- Built from the shortname rather than globbing, deliberately: folder
-- 3A6A6D27... carries a byte-identical duplicate "stillofthenight(0).mid"
-- beside the real one, so a *.mid glob returns 53 files for 52 songs. The dta's
-- own (song (name "songs/X/X")) field agrees with this construction and can be
-- used as a cross-check.
function SongMidiRelPath(shortname)
    return ('Root/songs/%s/%s.mid'):format(shortname, shortname)
end
