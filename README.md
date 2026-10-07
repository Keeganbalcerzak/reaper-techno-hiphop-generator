# REAPER Techno x Hip-Hop Generator

A [REAPER](https://www.reaper.fm) ReaScript (Lua) that writes a full 32-bar "techno hip-hop" track from scratch: 8 tracks with programmed MIDI, plus a Python script that synthesizes the drum kit it plays. No third-party samples or plugins are needed.

- **Techno**: four-on-the-floor kick, driving 16th hats, off-beat open hats, syncopated acid-ish bass.
- **Hip-hop**: half-time backbeat (snare/clap on 3), swung off-16ths, ghost snares, sub-bass slides.
- **Arrangement**: 32nd-note hat rolls, an evolving section structure, minor-key harmony (Cm9 / Abmaj7 / Fm9 / G7b9) with chord stabs, a walking arpeggio lead and a pad, with humanized velocity and timing (seeded, so it's reproducible).

The 8 tracks are Kick, Snare, Hats, Perc, Bass, Chords, Lead and Pad. The drums use REAPER's stock **ReaSamplOmatic5000** (one sampler per sound, pinned to its GM note) and the melodic parts use the stock **ReaSynth**, so the project plays as soon as the script finishes.

## Usage

1. Synthesize the drum kit (Python 3, standard library only):
   ```bash
   python synth_drumkit.py
   ```
   This writes 808/909-style one-shots (`kick`, `snare`, `clap`, `hatc`, `hato`, `congah`, `congal`, `clave`, `shaker`, plus a few extras) as WAVs into `samples/` next to the script.
2. In REAPER: **Actions > Show action list... > New action > Load ReaScript...**, pick `create_hiphop_techno.lua`, and run it. It's best to start from an empty project.
3. Press play.

The script finds `samples/` relative to its own location, so keep both files in the same folder. To use your own kit, change `SAMPLE_DIR` in the Lua file to a folder with the same file names. Tempo, length, swing and the random seed are set in the `CONFIG` block at the top of the Lua file.
