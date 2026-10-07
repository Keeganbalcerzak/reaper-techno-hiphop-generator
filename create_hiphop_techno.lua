--[[--------------------------------------------------------------------------
  create_hiphop_techno.lua
  A REAPER ReaScript (Lua) that builds a complete "techno hip-hop" hybrid track
  from scratch: tracks, tempo, and fully programmed MIDI.

  Fusion concept:
    * TECHNO   -> four-on-the-floor kick, driving 16th hats, off-beat open hats,
                  relentless syncopated acid-ish bass.
    * HIP-HOP  -> half-time backbeat (snare/clap on beat 3), swing on the
                  off-16ths, ghost snares, lazy sub-bass slides.
    * COMPLEX  -> 32nd-note hat rolls, evolving 8-bar arrangement, moody minor
                  harmony (Cm9 / Abmaj7 / Fm9 / G7b9) with stabs + a fast,
                  walking arpeggio lead, humanized velocity/timing.

  HOW TO RUN:
    0. Run `python synth_drumkit.py` once so samples/ exists next to this file.
    1. REAPER -> Actions -> Show action list... -> "New action" -> "Load ReaScript..."
    2. Pick this file, then run it. (Or: Actions -> Load ReaScript and Run.)
    3. It creates 8 tracks with MIDI, puts drum samplers on the drum tracks
       (GM map, notes 36/38/39/42/46/etc.) and ReaSynth on bass/chords/lead/pad.

  Everything below is MIDI only — no audio rendered. Tweak the CONFIG block.
----------------------------------------------------------------------------]]

----------------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------------
local BPM        = 124      -- techno tempo; half-time feel reads as ~62 hip-hop
local BARS       = 32       -- total length
local SWING      = 0.045    -- swing offset in quarter-notes, applied to off-16ths
local DRUM_CH    = 9        -- 0-indexed -> MIDI channel 10 (GM drums)
local SEED       = 20260621 -- deterministic "humanization"

math.randomseed(SEED)

local QN_PER_BAR = 4
local SIXTEENTH  = 0.25     -- in quarter-notes

----------------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------------
local function hum(v, amt)                 -- humanize a velocity around v
  amt = amt or 10
  local out = v + math.random(-amt, amt)
  if out < 1 then out = 1 elseif out > 127 then out = 127 end
  return math.floor(out)
end

local function barStartQN(bar) return (bar - 1) * QN_PER_BAR end

-- position of 16th step (0..15) within a bar, in QN, with optional swing
local function stepQN(bar, step, swing)
  local q = barStartQN(bar) + step * SIXTEENTH
  if swing and (step % 2 == 1) then q = q + SWING end
  return q
end

local function makeTrack(name)
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr
end

local secPerQN = 60.0 / BPM
local totalSec = BARS * QN_PER_BAR * secPerQN

local function makeItemTake(tr)
  local item = reaper.CreateNewMIDIItemInProj(tr, 0, totalSec, false)
  return reaper.GetActiveTake(item)
end

-- insert one note by quarter-note start/length
local function note(take, qnStart, qnLen, pitch, vel, chan)
  if pitch == nil then return end
  local s = reaper.MIDI_GetPPQPosFromProjQN(take, qnStart)
  local e = reaper.MIDI_GetPPQPosFromProjQN(take, qnStart + qnLen)
  reaper.MIDI_InsertNote(take, false, false, s, e, chan or 0, pitch, vel or 96, true)
end

----------------------------------------------------------------------------
-- HARMONY  (one chord per bar, 4-bar loop: i - VI - iv - V)
----------------------------------------------------------------------------
-- chord stab voicings (mid register), bass root, and a wide arp pool
local CHORDS = {
  { name="Cm9",   stab={60,63,67,70},    root=36, arp={60,63,67,70,72,75} },
  { name="Abmaj7",stab={56,60,63,67},    root=44, arp={56,60,63,67,72,75} },
  { name="Fm9",   stab={53,56,60,63},    root=41, arp={53,56,60,63,68,72} },
  { name="G7b9",  stab={55,59,62,65},    root=43, arp={55,59,62,65,68,71} },
}
local function chordForBar(bar) return CHORDS[((bar - 1) % 4) + 1] end

----------------------------------------------------------------------------
-- ARRANGEMENT  -> what plays in each bar (1-indexed)
----------------------------------------------------------------------------
local function section(bar)
  -- returns a table of feature flags + density knobs
  local s = {
    kick=true, snare=true, hats=true, openhats=true, perc=false,
    bass=false, chords=false, lead=false, pad=false,
    rolls=false, ghost=false, fill=false, density=1.0,
  }
  if bar <= 4 then                      -- INTRO: drums build in
    s.kick    = (bar >= 2)
    s.snare   = (bar >= 3)
    s.openhats= false
    s.density = 0.6
  elseif bar <= 12 then                 -- GROOVE
    s.bass=true; s.chords=true; s.perc=true; s.ghost=true
  elseif bar <= 16 then                 -- BUILD
    s.bass=true; s.chords=true; s.perc=true; s.lead=true
    s.ghost=true; s.rolls=true; s.pad=true
    s.fill = (bar == 16)
  elseif bar <= 24 then                 -- PEAK
    s.bass=true; s.chords=true; s.perc=true; s.lead=true; s.pad=true
    s.ghost=true; s.rolls=true; s.density=1.1
    s.fill = (bar == 24)
  elseif bar <= 28 then                 -- BREAKDOWN: drop the kick, keep musical
    s.kick=false; s.openhats=false; s.snare=(bar%2==0)
    s.chords=true; s.lead=true; s.pad=true; s.perc=true; s.density=0.7
  else                                  -- OUTRO CLIMAX
    s.bass=true; s.chords=true; s.perc=true; s.lead=true; s.pad=true
    s.ghost=true; s.rolls=true; s.density=1.1
    s.fill = (bar == 32)
  end
  return s
end

----------------------------------------------------------------------------
-- BUILD
----------------------------------------------------------------------------
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

reaper.SetCurrentBPM(0, BPM, false)
-- ensure a 4/4 tempo marker exists at the start
reaper.SetTempoTimeSigMarker(0, -1, 0, -1, -1, BPM, 4, 4, false)

local trKick   = makeTrack("KICK")
local trSnare  = makeTrack("SNARE / CLAP")
local trHats   = makeTrack("HI-HATS")
local trPerc   = makeTrack("PERC")
local trBass   = makeTrack("SUB BASS")
local trChords = makeTrack("CHORD STABS")
local trLead   = makeTrack("LEAD ARP")
local trPad    = makeTrack("PAD")

local tkKick   = makeItemTake(trKick)
local tkSnare  = makeItemTake(trSnare)
local tkHats   = makeItemTake(trHats)
local tkPerc   = makeItemTake(trPerc)
local tkBass   = makeItemTake(trBass)
local tkChords = makeItemTake(trChords)
local tkLead   = makeItemTake(trLead)
local tkPad    = makeItemTake(trPad)

-- GM drum notes
local KICK, SNARE, CLAP, RIM, GHOST = 36, 38, 39, 37, 38
local HH_CL, HH_OP, HH_PD          = 42, 46, 44
local CONGA_H, CONGA_L, CLAVE, SHKR= 63, 64, 75, 70

----------------------------------------------------------------------------
-- INSTRUMENTS
--   DRUMS  -> ReaSamplOmatic5000 (ships with REAPER) loaded with real 808/909
--             samples; one sampler instance per sound, pinned to its GM note,
--             note-offs ignored so one-shots ring fully.
--   MELODIC-> ReaSynth (ships with REAPER), tuned per role.
--   Samples are synthesized by synth_drumkit.py into samples/ next to this
--   script. To use your own kit, point SAMPLE_DIR at a folder with the same
--   file names (kick, snare, clap, hatc, hato, congah, congal, clave, shaker).
----------------------------------------------------------------------------
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:match("^(.*[\\/])") or ""
local SAMPLE_DIR = SCRIPT_DIR .. "samples"

-- find a plugin param by (case-insensitive substring of its) name
local function setParamByName(tr, fx, namesub, val)
  local n = reaper.TrackFX_GetNumParams(tr, fx)
  namesub = namesub:lower()
  for i = 0, n - 1 do
    local ok, pname = reaper.TrackFX_GetParamName(tr, fx, i, "")
    if ok and pname:lower():find(namesub, 1, true) then
      reaper.TrackFX_SetParamNormalized(tr, fx, i, val)
      return true
    end
  end
  return false
end

-- add a ReaSamplOmatic5000 to a track, load a sample, pin it to one MIDI note
local function addDrum(tr, midiNote, file)
  local fx = reaper.TrackFX_AddByName(tr, "ReaSamplOmatic5000", false, -1)
  if fx < 0 then return end
  reaper.TrackFX_SetNamedConfigParm(tr, fx, "FILE0", SAMPLE_DIR .. "/" .. file)
  reaper.TrackFX_SetNamedConfigParm(tr, fx, "DONE", "")
  setParamByName(tr, fx, "note range start", midiNote / 127)
  setParamByName(tr, fx, "note range end",   midiNote / 127)
  setParamByName(tr, fx, "obey",             0)   -- "Obey note-offs" off -> full one-shot
end

-- ReaSynth for the melodic tracks (params: 0 Vol,2 Atk,3 Dec,4 Sus,5 Rel)
local function loadSynth(tr, vol, attack, decay, sustain, release)
  local fx = reaper.TrackFX_AddByName(tr, "ReaSynth", false, -1)
  if fx < 0 then return end
  reaper.TrackFX_SetParamNormalized(tr, fx, 0, vol     or 0.5)
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, attack  or 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, decay   or 0.3)
  reaper.TrackFX_SetParamNormalized(tr, fx, 4, sustain or 0.5)
  reaper.TrackFX_SetParamNormalized(tr, fx, 5, release or 0.2)
end

-- DRUMS: one sampler per sound, mapped to the exact GM note used in the MIDI
addDrum(trKick,  36, "kick.wav")
addDrum(trSnare, 38, "snare.wav")   -- snare + ghosts (same note, lower velocity)
addDrum(trSnare, 39, "clap.wav")    -- 909 clap
addDrum(trSnare, 37, "snare.wav")   -- rim accent (reuses snare)
addDrum(trHats,  42, "hatc.wav")    -- closed hat
addDrum(trHats,  46, "hato.wav")    -- open hat
addDrum(trPerc,  63, "congah.wav")  -- hi conga (mid tom)
addDrum(trPerc,  64, "congal.wav")  -- lo conga (low tom)
addDrum(trPerc,  75, "clave.wav")   -- clave / cowbell
addDrum(trPerc,  70, "shaker.wav")  -- shaker (short hat)

-- MELODIC:           vol   atk    dec    sus    rel
loadSynth(trBass,   0.58, 0.00,  0.25,  0.55,  0.10)  -- punchy sub
loadSynth(trChords, 0.42, 0.00,  0.18,  0.30,  0.12)  -- stab
loadSynth(trLead,   0.45, 0.00,  0.20,  0.40,  0.10)  -- plucky lead
loadSynth(trPad,    0.38, 0.30,  0.40,  0.70,  0.45)  -- slow swell

for bar = 1, BARS do
  local s   = section(bar)
  local ch  = chordForBar(bar)

  ------------------------------------------------------------------ KICK
  if s.kick then
    -- four-on-the-floor (techno)
    for beat = 0, 3 do
      note(tkKick, barStartQN(bar) + beat, 0.22, KICK, hum(118, 6), DRUM_CH)
    end
    -- syncopated hip-hop ghost kicks on off-16ths
    if s.density >= 1.0 then
      note(tkKick, stepQN(bar, 7,  true), 0.2, KICK, hum(96, 8), DRUM_CH)
      note(tkKick, stepQN(bar, 14, true), 0.2, KICK, hum(90, 8), DRUM_CH)
    end
  end

  ------------------------------------------------------------------ SNARE / CLAP
  if s.snare then
    -- HALF-TIME backbeat: main snare+clap on beat 3 (the hip-hop signature)
    note(tkSnare, barStartQN(bar) + 2, 0.5, SNARE, hum(120, 6), DRUM_CH)
    note(tkSnare, barStartQN(bar) + 2, 0.5, CLAP,  hum(110, 8), DRUM_CH)
    -- ghost snares for swing/complexity
    if s.ghost then
      note(tkSnare, stepQN(bar, 6,  true), 0.12, GHOST, hum(45, 10), DRUM_CH)
      note(tkSnare, stepQN(bar, 11, true), 0.12, GHOST, hum(52, 10), DRUM_CH)
      if bar % 2 == 0 then
        note(tkSnare, stepQN(bar, 15, true), 0.12, GHOST, hum(58, 10), DRUM_CH)
      end
    end
    -- occasional rim accent
    if s.density >= 1.0 and bar % 4 == 3 then
      note(tkSnare, stepQN(bar, 10, true), 0.12, RIM, hum(70, 8), DRUM_CH)
    end
  end

  ------------------------------------------------------------------ HI-HATS
  if s.hats then
    for step = 0, 15 do
      local accent = (step % 4 == 2) and 24 or 0      -- push the off-beats
      local v = hum(70 + accent, 8)
      -- 32nd-note rolls on selected steps in busy sections (trap influence)
      if s.rolls and (step == 7 or step == 15) then
        local q0 = stepQN(bar, step, true)
        note(tkHats, q0,        0.10, HH_CL, hum(78, 6), DRUM_CH)
        note(tkHats, q0 + 0.125,0.10, HH_CL, hum(92, 6), DRUM_CH)
      else
        note(tkHats, stepQN(bar, step, true), 0.10, HH_CL, v, DRUM_CH)
      end
    end
    -- off-beat OPEN hats = the techno "tss" on the & of each beat
    if s.openhats then
      for _, step in ipairs({2, 6, 10, 14}) do
        note(tkHats, stepQN(bar, step, true), 0.22, HH_OP, hum(96, 8), DRUM_CH)
      end
    end
  end

  ------------------------------------------------------------------ PERC
  if s.perc then
    -- conga/clave syncopation + a shaker layer
    note(tkPerc, stepQN(bar, 3,  true), 0.15, CONGA_H, hum(78, 10), DRUM_CH)
    note(tkPerc, stepQN(bar, 5,  true), 0.15, CONGA_L, hum(70, 10), DRUM_CH)
    note(tkPerc, stepQN(bar, 9,  true), 0.15, CONGA_H, hum(82, 10), DRUM_CH)
    note(tkPerc, stepQN(bar, 13, true), 0.15, CONGA_L, hum(74, 10), DRUM_CH)
    if bar % 2 == 1 then
      note(tkPerc, stepQN(bar, 11, true), 0.12, CLAVE, hum(66, 8), DRUM_CH)
    end
    for _, step in ipairs({1, 5, 9, 13}) do
      note(tkPerc, stepQN(bar, step, true), 0.08, SHKR, hum(40, 8), DRUM_CH)
    end
  end

  ------------------------------------------------------------------ SUB BASS
  if s.bass then
    -- syncopated, octave-jumping acid-ish line keyed to the chord root
    local root = ch.root
    -- [step] = semitone offset from root (12 = up an octave, 7 = fifth)
    local pat = { [0]=0, [3]=0, [6]=12, [7]=0, [10]=7, [11]=0, [14]=12 }
    for step = 0, 15 do
      local off = pat[step]
      if off ~= nil then
        local len = (step == 0 or step == 7) and 0.45 or 0.22
        note(tkBass, stepQN(bar, step, true), len, root + off, hum(108, 6), 0)
      end
    end
    -- lazy hip-hop slide into the next bar on the last beat
    if bar % 4 == 0 then
      note(tkBass, barStartQN(bar) + 3.5, 0.4, root - 2, hum(96, 6), 0)
    end
  end

  ------------------------------------------------------------------ CHORD STABS
  if s.chords then
    -- short syncopated stabs on the off-grid (house/techno stab feel)
    for _, step in ipairs({2, 6, 9, 14}) do
      local v = hum(88, 8)
      for _, p in ipairs(ch.stab) do
        note(tkChords, stepQN(bar, step, true), 0.30, p, v, 0)
      end
    end
  end

  ------------------------------------------------------------------ LEAD ARP
  if s.lead then
    local pool = ch.arp
    -- index walk through the chord pool (with rests as 0) = complex melodic motion
    local pattern = {1,3,2,4, 1,5,3,6, 2,4,0,3, 5,4,6,2}
    for step = 0, 15 do
      local pi = pattern[step + 1]
      if pi ~= 0 then
        local p = pool[((pi - 1) % #pool) + 1]
        -- octave lift on accents for sparkle
        if step % 8 == 4 then p = p + 12 end
        local q0 = stepQN(bar, step, true)
        note(tkLead, q0, 0.20, p, hum(84, 10), 0)
        -- 32nd grace ornament in the busiest sections
        if s.rolls and (step == 6 or step == 12) then
          note(tkLead, q0 - 0.125, 0.10, p - 2, hum(60, 8), 0)
        end
      end
    end
  end

  ------------------------------------------------------------------ PAD
  if s.pad then
    -- sustained chord underneath, whole bar
    for _, p in ipairs(ch.stab) do
      note(tkPad, barStartQN(bar), QN_PER_BAR, p - 12, hum(64, 6), 0)
    end
  end

  ------------------------------------------------------------------ FILLS (end of section)
  if s.fill then
    -- snare/tom-style 16th run into the downbeat
    for step = 8, 15 do
      local v = hum(80 + (step - 8) * 5, 6)
      note(tkSnare, stepQN(bar, step, false), 0.12, SNARE, v, DRUM_CH)
    end
    -- open hat splash on the last 16th
    note(tkHats, stepQN(bar, 15, false), 0.4, HH_OP, hum(110, 6), DRUM_CH)
  end
end

-- finalize all takes
for _, tk in ipairs({tkKick,tkSnare,tkHats,tkPerc,tkBass,tkChords,tkLead,tkPad}) do
  reaper.MIDI_Sort(tk)
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.UpdateTimeline()
reaper.Undo_EndBlock("Generate techno hip-hop track", -1)

reaper.ShowMessageBox(
  "Done! 8 tracks at " .. BPM .. " BPM over " .. BARS .. " bars.\n\n" ..
  "Drums: synthesized 808/909-style samples in ReaSamplOmatic5000 (kick/snare/clap/hats/\n" ..
  "congas/clave/shaker). Melodic: ReaSynth. Hit play -- it's fully audible.\n\n" ..
  "Samples load from:\n" .. SAMPLE_DIR .. "\n" ..
  "If a drum is silent, run synth_drumkit.py first (or update SAMPLE_DIR).",
  "Techno Hip-Hop Generator", 0)
