-- Cross-instrument factor columns: one song's OTHER parts, as extra predictors.
--
-- Every model fitted so far predicts an instrument's official rank from that instrument's
-- own chart. This module supplies the join needed to ask whether the other parts of the
-- same song carry anything the target chart does not - the "cross-instrument chart
-- factors" thread in README.md's "Why three instruments still fail".
--
-- Pure: no r.*, no S, no ctx, no io. It takes an already-parsed CSV and returns tables.
-- The exporter, the shipped-vs-CSV parity tool and the probe would each otherwise build
-- this join separately, and a corpus artifact drifting from the test that validates it is
-- exactly the failure dev/tests/difficulty_suggester.lua exists to catch.
--
----------------------------------------------------------------------
-- WHY THE COLUMN NAME IS BUILT AND NEVER PARSED
----------------------------------------------------------------------
--
-- A cross column is named x_<src>_<key>, e.g. x_real_keys_total_changes. That name CANNOT
-- be split back into its parts: instrument names and factor names both contain
-- underscores, so x_real_keys_tight_p10 reads equally well as
--
--   src = 'real',      key = 'keys_tight_p10'
--   src = 'real_keys', key = 'tight_p10'
--
-- and no pattern distinguishes them. Every consumer therefore carries cross columns as
-- the RECORDS this module returns - { name, src, key } - and builds the name from the
-- parts. Nothing anywhere should match against '^x_(.-)_(.+)$'. This is the one mistake
-- the obvious implementation makes, and it fails silently: the wrong instrument's factor
-- is read and the fit still converges.
--
----------------------------------------------------------------------
-- CO-PRESENCE, MEASURED - which pairs are usable at all
----------------------------------------------------------------------
--
-- A row is usable only when the same song carries BOTH parts. Measured over the rb3_dlc
-- target rows of the 526-song corpus_scores.csv:
--
--   target (n)     guitar  bass  drum  keys  real_keys  vocals
--   keys (266)        263   266   264     -        266     264
--   real_keys (266)   263   266   264   266          -     264
--   vocals (328)      325   328   326   264        264       -
--   guitar (327)        -   327   325   263        263     325
--
-- The keyboard pair is 266/266 in BOTH directions - zero rows lost. That matters twice:
-- the comparison is against the same rows the published figures describe, and a future
-- protocol round adding these columns leaves every prior candidate's result unchanged,
-- because Collect drops a row only when a NAMED column is missing.
--
-- vocals <- keys or <- real_keys costs 64 of 328 rows (19.5%) and is refused for that
-- reason, not as a preference. Every vocals figure in such a round would describe a
-- different row set from every vocals figure already published, and the shift in the
-- interval lower bound would exceed the effect being measured.
--
----------------------------------------------------------------------
-- THE COLUMN VOCABULARY
----------------------------------------------------------------------
--
-- ONE triple, used identically for every (target, source) pair, so there is no per-pair
-- search anywhere - picking different columns per pair would be fishing dressed as a
-- declaration, and this corpus has already shown (README's deathontwolegs case) what a
-- wide fit does with one extreme row.
--
-- Three columns against the keys model's seven is 43% more features at n=266. That is
-- near the limit this corpus supports and is the reason there is no fourth.
CROSS_COLUMNS = {
    -- How fast the part plays at its busiest. The closest thing the factor set has to
    -- "how hard is this song", and it counts attacks, so it means the same on a keyboard
    -- and on a fretboard.
    'attack_density_peak',

    -- Volume of distinct material.
    'total_changes',

    -- The one factor protocol.lua already states means the same thing on every
    -- instrument, voice included - which is what lets a single vocabulary be honest.
    'entropy_h2_rel',
}

----------------------------------------------------------------------
-- THE SECOND VOCABULARY, AND WHY THE FIRST ONE NEEDED IT
----------------------------------------------------------------------
--
-- CROSS_COLUMNS above tests almost nothing on the keyboard pair, and that was not visible
-- until it was run. Measured ratio of the Pro Keys value to the 5-lane keys value, median
-- over all 266 songs carrying both:
--
--   total_changes        1.00      attack_density_peak  1.00
--   playing_s            1.00      tight_p10            1.00
--   density_peak         1.01      notes_total          1.05
--   chord_size_mean      1.05      entropy_h2_rel       0.81
--   move_mean            2.53      chord_span_mean      3.19
--
-- The 5-lane reduction preserves WHEN the player plays, exactly, and compresses WHERE.
-- That is precisely what reducing a 25-key range to five lanes does, and it means two of
-- the three columns in the first vocabulary are the SAME NUMBER on both charts. A probe
-- built from them is adding duplicate columns and can only measure regularisation noise -
-- which is what it found.
--
-- So this second set is not a second guess at the same question. It is the first honest
-- test of it: the columns where the reduction demonstrably loses information, identified
-- by the measurement above BEFORE any of them was fitted, so the choice is a
-- consequence of measured redundancy rather than a search for a column that scores well.
--
-- Keyboard pair only. On vocals there is no reduction relationship to exploit - guitar and
-- drums are different parts, not a lossy encoding of the singing - so the geometry
-- argument does not apply and the vocals result stands on the first vocabulary.
CROSS_COLUMNS_GEOMETRY = {
    'chord_span_mean',   -- 3.19x: how far apart the outer notes of a shape really sit
    'move_mean',         -- 2.53x: how far the hand actually travels between attacks
    'entropy_h2_rel',    -- 0.81x: the only member of the first set that is not a duplicate
}

-- A cross column as a record. Build names with this; never take one apart.
function CrossCol(src, key)
    return { name = 'x_' .. src .. '_' .. key, src = src, key = key }
end

-- One source instrument's columns, as records. `cols` defaults to CROSS_COLUMNS.
function CrossColsFor(src, cols)
    local out = {}
    for _, key in ipairs(cols or CROSS_COLUMNS) do out[#out + 1] = CrossCol(src, key) end
    return out
end

-- factor_by_song[shortname][instrument][factor_key] = number
--
-- Built from every row in the CSV regardless of origin: a source part is evidence about
-- the song whether or not that part is itself a training target, so an aux-origin row can
-- still supply a column for an rb3_dlc target row of the same song. Which rows are
-- TRAINED on is the caller's partition to make, not this join's.
--
-- `Field(row, name)` is passed in rather than reimplemented, so the probe and any later
-- consumer keep using their own CSV accessor.
function BuildFactorBySong(csv, Field)
    -- The UNION of every declared vocabulary, so adding a column to one of them cannot
    -- leave the join silently short of it - a missing key here reads as "the song has no
    -- such part" and would drop rows rather than raise.
    local wanted, seen = {}, {}
    for _, set in ipairs({ CROSS_COLUMNS, CROSS_COLUMNS_GEOMETRY }) do
        for _, key in ipairs(set) do
            if not seen[key] then seen[key] = true ; wanted[#wanted + 1] = key end
        end
    end

    local by_song = {}
    for _, row in ipairs(csv.rows) do
        local name = Field(row, 'shortname')
        local inst = Field(row, 'instrument')
        if name and inst then
            by_song[name] = by_song[name] or {}
            local slot = by_song[name][inst] or {}
            by_song[name][inst] = slot
            for _, key in ipairs(wanted) do
                local v = tonumber(Field(row, key))
                if v then slot[key] = v end
            end
        end
    end
    return by_song
end

-- The value for one cross column on one song, or nil when the song has no such part.
-- nil is what makes the caller drop the row, so it must not be defaulted to 0 here: a
-- missing part and a part measuring zero are different facts.
function CrossValue(by_song, shortname, col)
    local per_inst = by_song[shortname]
    if not per_inst then return nil end
    local slot = per_inst[col.src]
    if not slot then return nil end
    return slot[col.key]
end
