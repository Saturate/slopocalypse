//! `VoxelGround`: ground tiles meshed from coarse heights and colours, right away
//! (`tile_arrays`) or on the extension's own mesher threads (`mesh_start` ... `mesh_take`).
//! gdext refuses calls from Godot's worker threads, so the game can't mesh a tile on one;
//! the inputs are copied out of Godot's types on the main thread instead, meshed here on a
//! plain Rust thread, and handed back as ready buffers for the main thread to wrap.

use super::{colour_of, shading, to_color};
use godot::classes::mesh::ArrayType;
use godot::prelude::*;
use std::collections::HashMap;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, LazyLock, Mutex, OnceLock};
use std::thread;
use voxkit_core::heightfield::{self, Tile};
use voxkit_core::ways::Look;
use voxkit_core::{Colour, OPEN};

/// Everything a tile is meshed from, owned, so a mesher thread can take it.
struct TileInput {
    heights: Vec<f32>,
    cn: usize,
    spacing: f32,
    colours: Vec<Colour>,
    cc: usize,
    n: usize,
    voxel: f32,
    steep_slope: f32,
    steep: Colour,
    side: Colour,
    skirt: f32,
    seed: u32,
    /// Brightness per corner level when corner shading is on.
    levels: Option<[f32; 4]>,
    tilt_grade: f32,
    band: f32,
    pad_band: f32,
    band_grade: f32,
    ledge: f32,
    ledge_grade: f32,
    ways: Vec<f32>,
    look: Look,
    dug: Vec<u8>,
}

/// A meshed tile in Godot's layout, made without calling into Godot.
#[derive(Default)]
struct TileBuffers {
    vertices: Vec<Vector3>,
    normals: Vec<Vector3>,
    colours: Vec<Color>,
    indices: Vec<i32>,
}

#[allow(clippy::too_many_arguments)]
fn tile_input(
    heights: &PackedFloat32Array,
    cn: i64,
    spacing: f32,
    colours: &PackedColorArray,
    cc: i64,
    n: i64,
    voxel: f32,
    seed: i64,
    look: &VarDictionary,
    ways: &PackedFloat32Array,
    dug: &PackedByteArray,
) -> Option<TileInput> {
    let (cn, cc, n) = (
        cn.max(2) as usize,
        cc.max(2) as usize,
        n.clamp(1, 1024) as usize,
    );
    if heights.len() < cn * cn || colours.len() < cc * cc {
        godot_error!("VoxelGround: heights or colours shorter than the grid");
        return None;
    }
    let number = |key: &str, fallback: f32| look_number(look, key, fallback);
    Some(TileInput {
        heights: heights.as_slice().to_vec(),
        cn,
        spacing,
        colours: colours.as_slice().iter().map(|&c| colour_of(c)).collect(),
        cc,
        n,
        voxel: voxel.max(0.01),
        steep_slope: number("steep_slope", f32::INFINITY),
        steep: look_colour(look, "steep", 0x77_77_77),
        side: look_colour(look, "side", 0x55_33_11),
        skirt: number("skirt", 0.0),
        seed: seed as u32,
        levels: shading(),
        tilt_grade: number("tilt_grade", 0.0),
        band: number("band", 0.0),
        pad_band: number("pad_band", 0.0),
        band_grade: number("band_grade", 0.0),
        ledge: number("ledge", 0.0),
        ledge_grade: number("ledge_grade", f32::INFINITY),
        ways: ways.as_slice().to_vec(),
        look: look_of(look),
        dug: dug.as_slice().to_vec(),
    })
}

/// Meshes `t`. Touches no Godot API (only gdext's plain value types), so it runs on any
/// thread.
fn mesh_tile(t: &TileInput) -> TileBuffers {
    let tile = Tile {
        heights: &t.heights,
        cn: t.cn,
        spacing: t.spacing,
        colours: &t.colours,
        cc: t.cc,
        n: t.n,
        voxel: t.voxel,
        steep_slope: t.steep_slope,
        steep: t.steep,
        side: t.side,
        skirt: t.skirt,
        seed: t.seed,
        corners: t.levels.is_some(),
        tilt_grade: t.tilt_grade,
        band: t.band,
        pad_band: t.pad_band,
        band_grade: t.band_grade,
        ledge: t.ledge,
        ledge_grade: t.ledge_grade,
        ways: &t.ways,
        look: t.look,
        dug: &t.dug,
    };
    let (mesh, tilted) = heightfield::mesh_marked(&tile);
    if mesh.indices.is_empty() {
        return TileBuffers::default();
    }
    let levels = t.levels.unwrap_or([1.0; 4]);
    // Alpha marks how the ground shader draws a vertex: 1 plain, 0.75 painted by a way,
    // 0.25 a sloping tilted top (varied per column), 0 both.
    let colours = mesh
        .colours
        .iter()
        .zip(mesh.shade.iter().chain(std::iter::repeat(&OPEN)))
        .enumerate()
        .map(|(i, (&c, &l))| {
            let painted = l & heightfield::PAINTED != 0;
            let k = levels[usize::from((l & !heightfield::PAINTED).min(OPEN))];
            let col = to_color(c);
            let a = match (tilted.contains(&i), painted) {
                (true, true) => 0.0,
                (true, false) => 0.25,
                (false, true) => 0.75,
                (false, false) => col.a,
            };
            Color::from_rgba(col.r * k, col.g * k, col.b * k, a)
        })
        .collect();
    TileBuffers {
        vertices: mesh
            .positions
            .iter()
            .map(|p| Vector3::new(p[0], p[1], p[2]))
            .collect(),
        normals: mesh
            .normals
            .iter()
            .map(|n| Vector3::new(n[0], n[1], n[2]))
            .collect(),
        colours,
        indices: mesh.indices.iter().map(|&i| i as i32).collect(),
    }
}

/// Arrays for `ArrayMesh.add_surface_from_arrays`, or empty when there is nothing to draw.
fn arrays_of(b: &TileBuffers) -> VarArray {
    if b.indices.is_empty() {
        return VarArray::new();
    }
    let mut arrays = VarArray::new();
    arrays.resize(ArrayType::MAX.ord() as usize, &Variant::nil());
    let set = |arrays: &mut VarArray, slot: ArrayType, value: Variant| {
        arrays.set(slot.ord() as usize, &value);
    };
    set(
        &mut arrays,
        ArrayType::VERTEX,
        PackedVector3Array::from(b.vertices.as_slice()).to_variant(),
    );
    set(
        &mut arrays,
        ArrayType::NORMAL,
        PackedVector3Array::from(b.normals.as_slice()).to_variant(),
    );
    set(
        &mut arrays,
        ArrayType::COLOR,
        PackedColorArray::from(b.colours.as_slice()).to_variant(),
    );
    set(
        &mut arrays,
        ArrayType::INDEX,
        PackedInt32Array::from(b.indices.as_slice()).to_variant(),
    );
    arrays
}

/// A tile handed to the mesher threads: waiting, meshed, or failed (the mesher panicked; the
/// main thread reports it, as a mesher thread can't call into Godot). A dropped one has no
/// entry.
enum Slot {
    Waiting,
    Done(TileBuffers),
    Failed,
}

static SLOTS: LazyLock<Mutex<HashMap<i64, Slot>>> = LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_ID: AtomicI64 = AtomicI64::new(1);
static QUEUE: OnceLock<Mutex<Sender<(i64, TileInput)>>> = OnceLock::new();

fn slots() -> std::sync::MutexGuard<'static, HashMap<i64, Slot>> {
    // A mesher that panicked holding the lock leaves plain data behind: still usable.
    SLOTS.lock().unwrap_or_else(|e| e.into_inner())
}

/// The mesher threads, started on first use. Godot's worker pool already keeps every core
/// busy with ground and scenery sampling, so meshing gets a few threads of its own, at most
/// half the cores: enough to keep up with a car (a tile is a few milliseconds at most).
fn queue() -> &'static Mutex<Sender<(i64, TileInput)>> {
    QUEUE.get_or_init(|| {
        let (send, receive) = channel::<(i64, TileInput)>();
        let receive = Arc::new(Mutex::new(receive));
        let count = thread::available_parallelism()
            .map_or(2, |n| n.get() / 2)
            .clamp(1, 4);
        for k in 0..count {
            let receive = Arc::clone(&receive);
            let spawned = thread::Builder::new()
                .name(format!("ground mesher {k}"))
                .spawn(move || mesher(&receive));
            if spawned.is_err() {
                godot_error!("VoxelGround: could not start a mesher thread");
            }
        }
        Mutex::new(send)
    })
}

fn mesher(receive: &Mutex<Receiver<(i64, TileInput)>>) {
    loop {
        let next = receive.lock().unwrap_or_else(|e| e.into_inner()).recv();
        let Ok((id, input)) = next else {
            return;
        };
        // Dropped while it waited: not worth meshing.
        if !slots().contains_key(&id) {
            continue;
        }
        // A panic must not take the thread (and every tile queued behind it) down: the tile
        // comes back failed instead.
        let meshed = catch_unwind(AssertUnwindSafe(|| mesh_tile(&input)));
        if let Some(slot) = slots().get_mut(&id) {
            *slot = meshed.map_or(Slot::Failed, Slot::Done);
        }
    }
}

/// Voxel ground tiles: turns coarse heights and colours over a tile into blocky columns (see
/// voxkit_core::heightfield), right away with `tile_arrays` or on mesher threads with
/// `mesh_start`, `mesh_ready`, `mesh_take` and `mesh_drop`.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct VoxelGround {
    base: Base<RefCounted>,
}

#[godot_api]
impl VoxelGround {
    /// `heights` is `cn` x `cn` (row-major by z), `spacing` metres apart; `colours` is
    /// `cc` x `cc` over the same tile; the tile is `n` columns of `voxel` metres a side.
    /// `look` holds the ground's settings: `steep_slope` (rise over run past which `steep`
    /// shows), `side` (the colour of tall walls), `skirt`, `tilt_grade`, `band`, `pad_band`,
    /// `band_grade`, `ledge`, `ledge_grade` (see `voxkit_core::heightfield::Tile`) and how ways are drawn (see
    /// `look_of`). `ways` holds the roads, tracks, lanes and pads over the tile
    /// (`voxkit_core::ways::WAY_STRIDE` floats each, tile-local); `dug` is non-zero per
    /// height sample where a crater was dug (or empty). Returns mesh arrays in tile-local
    /// metres; colour alpha marks sloping tilted tops and painted columns (see `mesh_tile`).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn tile_arrays(
        heights: PackedFloat32Array,
        cn: i64,
        spacing: f32,
        colours: PackedColorArray,
        cc: i64,
        n: i64,
        voxel: f32,
        seed: i64,
        look: VarDictionary,
        ways: PackedFloat32Array,
        dug: PackedByteArray,
    ) -> VarArray {
        match tile_input(
            &heights, cn, spacing, &colours, cc, n, voxel, seed, &look, &ways, &dug,
        ) {
            Some(input) => arrays_of(&mesh_tile(&input)),
            None => VarArray::new(),
        }
    }

    /// `tile_arrays` on a mesher thread: returns a job id for `mesh_ready` and `mesh_take`
    /// (0 when the input is bad). Every id must end in `mesh_take` or `mesh_drop`.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn mesh_start(
        heights: PackedFloat32Array,
        cn: i64,
        spacing: f32,
        colours: PackedColorArray,
        cc: i64,
        n: i64,
        voxel: f32,
        seed: i64,
        look: VarDictionary,
        ways: PackedFloat32Array,
        dug: PackedByteArray,
    ) -> i64 {
        let Some(input) = tile_input(
            &heights, cn, spacing, &colours, cc, n, voxel, seed, &look, &ways, &dug,
        ) else {
            return 0;
        };
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        slots().insert(id, Slot::Waiting);
        let sent = queue()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .send((id, input));
        if sent.is_err() {
            slots().remove(&id);
            godot_error!("VoxelGround: no mesher thread to take the tile");
            return 0;
        }
        id
    }

    /// Whether job `id` has been meshed (true for an unknown id, so nobody waits on it).
    #[func]
    fn mesh_ready(id: i64) -> bool {
        !matches!(slots().get(&id), Some(Slot::Waiting))
    }

    /// Job `id`'s arrays (as `tile_arrays` returns them), and the job is forgotten; empty
    /// while it is still meshing (check `mesh_ready`), for an unknown id, for a tile with
    /// nothing to draw, or when meshing failed (reported as an error).
    #[func]
    fn mesh_take(id: i64) -> VarArray {
        let mut slots = slots();
        if matches!(slots.get(&id), Some(Slot::Waiting) | None) {
            return VarArray::new();
        }
        let taken = slots.remove(&id);
        drop(slots);
        match taken {
            Some(Slot::Done(buffers)) => arrays_of(&buffers),
            _ => {
                godot_error!("VoxelGround: meshing a ground tile failed");
                VarArray::new()
            }
        }
    }

    /// Forgets job `id`, done or not: its result is thrown away.
    #[func]
    fn mesh_drop(id: i64) {
        slots().remove(&id);
    }

    /// How many jobs are waiting or meshed but not taken (for tests: dropped and taken jobs
    /// leave nothing behind).
    #[func]
    fn mesh_jobs() -> i64 {
        slots().len() as i64
    }
}

fn look_colour(look: &VarDictionary, key: &str, fallback: Colour) -> Colour {
    look.get(key)
        .and_then(|v| v.try_to::<Color>().ok())
        .map_or(fallback, colour_of)
}

fn look_number(look: &VarDictionary, key: &str, fallback: f32) -> f32 {
    look.get(key)
        .and_then(|v| v.try_to::<f32>().ok())
        .unwrap_or(fallback)
}

/// How the ground draws ways, from `look` (keys as `voxkit_core::ways::Look`'s fields,
/// colours as Color); anything missing keeps its default.
fn look_of(look: &VarDictionary) -> Look {
    let d = Look::default();
    let number = |key: &str, fallback: f32| look_number(look, key, fallback);
    let colour = |key: &str, fallback: Colour| look_colour(look, key, fallback);
    Look {
        paved_bed: colour("paved_bed", d.paved_bed),
        track_soil: colour("track_soil", d.track_soil),
        strip_top: number("strip_top", d.strip_top),
        track_fray: number("track_fray", d.track_fray),
        track_verge: number("track_verge", d.track_verge),
        yard_fray: number("yard_fray", d.yard_fray),
        yard_round: number("yard_round", d.yard_round),
        lane_soil: colour("lane_soil", d.lane_soil),
        lane_mix: number("lane_mix", d.lane_mix),
        verge_mix: number("verge_mix", d.verge_mix),
        rut_dark: number("rut_dark", d.rut_dark),
    }
}
