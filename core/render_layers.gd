class_name RenderLayers
extends RefCounted
## Visual layers with a shared meaning across modules. Kept free of autoloads so builders
## can use it.

## Overlays for the main view only (world-space labels): scope and other secondary cameras
## leave this layer out, so a magnified picture is not covered by a magnified label.
const MAIN_VIEW_ONLY := 20


## The bit for `layer` (1-based, as the editor numbers them) in a cull or visual mask.
static func bit(layer: int) -> int:
	return 1 << (layer - 1)
