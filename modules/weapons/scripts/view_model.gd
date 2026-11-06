class_name ViewModel
extends RefCounted
## Shared constant for first-person view models. Standalone on purpose: builders cannot
## compile scripts that name autoloads, so this must not live in HitscanWeapon.

## Render layer bit for view models (layer 2). The camera sees it by default; world
## lights that would glare on the gun, such as the muzzle flash, leave it out.
const LAYER := 1 << 1
