class_name BodyLod
extends RefCounted
## Client: how often someone else's body (another player, a soldier, a civilian) is posed.
## Posing a body (its animation, aim and hands on the gun) is most of what a crowd costs a
## client, and a pose redone every frame for a figure 40 m off or behind the camera shows
## nothing new. Up close and in view it is every frame; past `near_distance`, out of view,
## a few times a second. Movement itself stays smooth: only the pose is held between updates.

const CONFIG := "res://modules/player/data/body_lod.json"
const PLAYER_CONFIG := "res://modules/player/data/player.json"
const REQUIRED := {
	"near_distance": TYPE_FLOAT,
	"far_distance": TYPE_FLOAT,
	"mid_rate": TYPE_FLOAT,
	"far_rate": TYPE_FLOAT,
	"off_screen_rate": TYPE_FLOAT,
	"view_radius": TYPE_FLOAT,
}
## Rates below this would leave a body frozen for seconds; data can't go lower.
const MIN_RATE := 1.0

var near_distance := 15.0
var far_distance := 40.0
var mid_rate := 30.0
var far_rate := 15.0
var off_screen_rate := 10.0
var view_radius := 1.2
## The field of view distances are judged at; a narrower one (a scope) brings bodies closer.
var reference_fov := 80.0

static var _shared: BodyLod

# The view, worked out once a frame and shared by every body.
var _view_frame := -1
var _view_camera_id := 0
var _camera: Camera3D
var _planes: Array[Plane] = []
var _eye := Vector3.ZERO
var _zoom := 1.0


## The one every body uses, loaded from the data on first use.
static func shared() -> BodyLod:
	if _shared == null:
		_shared = BodyLod.new()
		_shared._load()
	return _shared


func _load() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if data is Dictionary and Data.require(CONFIG, data, REQUIRED):
		near_distance = float(data["near_distance"])
		far_distance = float(data["far_distance"])
		mid_rate = maxf(float(data["mid_rate"]), MIN_RATE)
		far_rate = maxf(float(data["far_rate"]), MIN_RATE)
		off_screen_rate = maxf(float(data["off_screen_rate"]), MIN_RATE)
		view_radius = float(data["view_radius"])
	var player: Variant = Data.load_json(PLAYER_CONFIG)
	if player is Dictionary and Data.require(PLAYER_CONFIG, player, {"fov": TYPE_FLOAT}):
		var fov := float(player["fov"])
		# tan() of half of it must be finite and positive.
		if fov > 1.0 and fov < 179.0:
			reference_fov = fov
		else:
			Log.warn(&"player", "%s: fov %.1f is out of range; distances are judged at %.0f degrees" % [PLAYER_CONFIG, fov, reference_fov])


## Seconds between poses for a body `distance` metres off (already scaled by the zoom), in
## view or not; 0 is every frame.
func interval(distance: float, on_screen: bool) -> float:
	if not on_screen:
		return 1.0 / off_screen_rate
	if distance < near_distance:
		return 0.0
	if distance < far_distance:
		return 1.0 / mid_rate
	return 1.0 / far_rate


## How much nearer things look through a camera with this field of view than at the
## reference one: below 1 when zoomed in.
func zoom_for(fov_degrees: float) -> float:
	return tan(deg_to_rad(fov_degrees) * 0.5) / tan(deg_to_rad(reference_fov) * 0.5)


## Seconds between poses for a body whose middle is at `at`, seen through `viewport`'s
## camera; 0 (every frame) when there is no camera to judge by.
func interval_at(viewport: Viewport, at: Vector3) -> float:
	_refresh(viewport)
	if _camera == null:
		return 0.0
	var on_screen := true
	for plane in _planes:
		if plane.distance_to(at) > view_radius:
			on_screen = false
			break
	return interval(_eye.distance_to(at) * _zoom, on_screen)


func _refresh(viewport: Viewport) -> void:
	var frame := Engine.get_process_frames()
	var camera := viewport.get_camera_3d() if viewport != null else null
	var id := camera.get_instance_id() if camera != null else 0
	if frame == _view_frame and id == _view_camera_id:
		return
	_view_frame = frame
	_view_camera_id = id
	_camera = camera
	if camera == null:
		return
	_planes.assign(camera.get_frustum())
	_eye = camera.global_position
	_zoom = zoom_for(camera.fov) if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else 1.0
