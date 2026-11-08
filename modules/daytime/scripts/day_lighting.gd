class_name DayLighting
extends Node
## Client-only: points the world's light at the sun by day and the moon by night, and
## recolours the sky, ambient light and fog for the hour. Applied every `update_seconds`
## rather than every frame: the sky re-renders its lighting whenever it changes.

const STAR_SIZE := Vector2i(2048, 1024)
const STAR_COUNT := 4500
## Stars brighter than this are drawn two pixels wide so they survive the screen scaling.
const BIG_STAR := 0.55
const STAR_SEED := 7

var sun: DirectionalLight3D
var environment: Environment

var _sky: ProceduralSkyMaterial


## Takes over the world's sun and environment (null when the world is not loaded).
func attach(light: DirectionalLight3D, env: Environment) -> void:
	sun = light
	environment = env
	_sky = null
	if environment != null and environment.sky != null:
		_sky = environment.sky.sky_material as ProceduralSkyMaterial
	if _sky != null:
		_sky.sky_cover = _stars()


func apply(clock: DayClock) -> void:
	var look := clock.look()
	if sun != null:
		sun.basis = clock.light_basis()
		sun.light_color = look["light_color"]
		sun.light_energy = look["light_energy"]
	if environment == null:
		return
	# A dark night sky gives almost no ambient light by itself, so part of it comes from a
	# plain colour: moonlit blue at night, the sky by day.
	environment.ambient_light_energy = look["ambient"]
	environment.ambient_light_color = look["ambient_color"]
	environment.ambient_light_sky_contribution = look["sky_light"]
	environment.tonemap_exposure = look["exposure"]
	var fog: Color = look["fog_color"]
	environment.fog_light_color = fog
	environment.fog_density = look["fog_density"]
	environment.volumetric_fog_albedo = fog.lerp(Color.WHITE, 0.3)
	if _sky != null:
		_sky.sky_top_color = look["sky_top"]
		_sky.sky_horizon_color = look["sky_horizon"]
		_sky.ground_horizon_color = look["sky_horizon"]
		_sky.ground_bottom_color = look["ground"]
		_sky.sky_cover_modulate = Color(1.0, 1.0, 1.0, float(look["stars"]))


## A starfield for the sky cover: faint dots, a few bright ones, the same every run.
static func _stars() -> ImageTexture:
	var image := Image.create(STAR_SIZE.x, STAR_SIZE.y, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for i in STAR_COUNT:
		var brightness := pow(rng.randf(), 3.0) * 0.9 + 0.1
		var tint := Color(1.0, 1.0, 1.0).lerp(Color(0.75, 0.85, 1.0), rng.randf())
		var x := rng.randi_range(0, STAR_SIZE.x - 2)
		var y := rng.randi_range(0, STAR_SIZE.y - 2)
		var size := 2 if brightness > BIG_STAR else 1
		image.fill_rect(Rect2i(x, y, size, size), tint * brightness)
	return ImageTexture.create_from_image(image)
