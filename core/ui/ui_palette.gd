class_name UiPalette
extends RefCounted
## The one palette and type scale every screen uses: worn olive steel, warm paper-white text
## and one amber accent. Sizes are in pixels at the 1600x900 base resolution; the window's
## canvas_items stretch scales them with the window.

const BACKGROUND := Color("16180f")
## Behind an open screen, over the game.
const BACKDROP := Color(0.03, 0.035, 0.025, 0.8)
const STEEL := Color("3b4034")
const STEEL_RAISED := Color("4a5040")
const STEEL_SUNK := Color("2c3027")
## Paint chipped off down to the metal.
const STEEL_BARE := Color("8d8f86")
const TAPE := Color("d9cfae")
## Dark text on tape and on the accent.
const INK := Color("1d1c18")
const SHADOW := Color(0, 0, 0, 0.55)

const TEXT := Color("ece6d6")
const DIM := Color("a49f8e")
const ACCENT := Color("f2a516")
const GOOD := Color("8fc25a")
const BAD := Color("e0452b")
const WARN := Color("f5c542")

const TITLE := 44
const HEADING := 28
const BODY := 20
const HINT := 16
const HUD := 18
const HUD_NUMBER := 40
