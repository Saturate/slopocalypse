class_name UiLayers
extends RefCounted
## CanvasLayer order for everything drawn over the game, lowest first. Named here so a new
## overlay finds its place instead of picking a number.

const HUD := 3
## Interaction prompts and the thermal tint sit just over the HUD.
const PROMPTS := 4
const SCOPE := 5
const SCREENS := 40
## Loot opens over the inventory.
const LOOT := 41
const MISSION_BOARD := 42
const TRADER := 43
const PERF := 45
## The Esc menu and the connecting card, over every screen.
const SESSION := 50
## The ride fade covers everything, menus included.
const FADE := 60
