# Recorded sounds

Drop a recording here and the game plays it instead of the sound it makes in code. Sounds without a recording keep the generated one, so recordings can land one at a time.

## Names

- `<id>.ogg`: one recording for the sound `<id>`.
- `<id>_1.ogg`, `<id>_2.ogg`, ...: several takes; each play picks one at random.
- The ids are the ones `SoundBank` makes and `modules/audio/data/audio.json` lists under `volume_db`: `rifle`, `pistol`, `bolt_rifle`, `suppressed`, `explosion`, `footstep`, `wind`, `bird0` to `bird3`, `hit_wood`, `break_glass` and so on.
- Ogg Vorbis only. Mono for anything placed in the world (shots, impacts, footsteps); `wind` and `crickets` may be stereo.
- `wind`, `rotor` and `crickets` loop: cut them so the end runs into the start.

Each play is pitched and turned up or down a little (`jitter` in `audio.json`), so one take doesn't repeat audibly. Level a recording with `volume_db` in the same file.

In an exported game, `tweaks/modules/audio/sounds/` beside the executable works the same way: takes of a sound there replace the built-in ones for that sound.

## Licences

CC0 or CC BY only (freesound.org has plenty). Ask the maintainer before using anything under another licence, including packs with their own terms.

Every file gets a row in `assets/LICENSES.md` with the file, what it is and its author, the source link and the licence; see "Recorded sounds" there.
