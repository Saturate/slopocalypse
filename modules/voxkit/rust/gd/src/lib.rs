//! gdext binding for voxkit_core: GDScript gets `VoxelModel`, a grid generators fill with
//! shapes in metres and turn into an ArrayMesh.

// gdext's entry point must be an `unsafe impl` and its macro drops item-level allows, so
// binding crates allow unsafe at crate level. Pure crates keep it denied; keep logic there.
#![allow(unsafe_code)]

use godot::classes::mesh::ArrayType;
use godot::prelude::*;
use voxkit_core::heightfield::{self, Tile};
use voxkit_core::{Colour, Grid, Mesh, Op, Paint};

struct VoxkitExtension;

#[gdextension]
unsafe impl ExtensionLibrary for VoxkitExtension {}

/// GDScript: `var m := VoxelModel.new(); m.setup(Vector3(2, 10, 2), 0.1)`, then fills, then
/// `mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.mesh_arrays())`.
/// Colours are sRGB; `jitter` (0 to 1) varies each cell's brightness, seeded by `seed`.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct VoxelModel {
    grid: Option<Grid>,
    /// Multiplies every fill's colour jitter: 0 gives flat colours, 1 what the generator asked.
    #[init(val = 1.0)]
    jitter_scale: f32,
    base: Base<RefCounted>,
}

#[godot_api]
impl VoxelModel {
    /// A model `size` metres across (x, y, z) at `voxel` metres per cell. y starts at the
    /// ground; x and z are centred.
    #[func]
    fn setup(&mut self, size: Vector3, voxel: f32) {
        self.grid = Some(Grid::new(v3(size), voxel));
    }

    #[func]
    fn fill_box(&mut self, min: Vector3, max: Vector3, colour: Color, jitter: f32, seed: i64) {
        self.with(|g, k| g.fill_box(v3(min), v3(max), Op::Fill(paint(colour, jitter * k, seed))));
    }

    #[func]
    fn fill_ellipsoid(
        &mut self,
        centre: Vector3,
        radii: Vector3,
        colour: Color,
        jitter: f32,
        seed: i64,
    ) {
        self.with(|g, k| {
            g.fill_ellipsoid(
                v3(centre),
                v3(radii),
                Op::Fill(paint(colour, jitter * k, seed)),
            )
        });
    }

    #[func]
    #[allow(clippy::too_many_arguments)]
    fn fill_capsule(
        &mut self,
        a: Vector3,
        b: Vector3,
        ra: f32,
        rb: f32,
        colour: Color,
        jitter: f32,
        seed: i64,
    ) {
        self.with(|g, k| {
            g.fill_capsule(
                v3(a),
                v3(b),
                ra,
                rb,
                Op::Fill(paint(colour, jitter * k, seed)),
            )
        });
    }

    #[func]
    #[allow(clippy::too_many_arguments)]
    fn fill_cylinder(
        &mut self,
        base: Vector3,
        radius: f32,
        height: f32,
        colour: Color,
        jitter: f32,
        seed: i64,
    ) {
        self.with(|g, k| {
            g.fill_cylinder(
                v3(base),
                radius,
                height,
                Op::Fill(paint(colour, jitter * k, seed)),
            )
        });
    }

    /// An ellipsoid with a noisy surface: `bumps` is how far (as a share of the radius) the
    /// noise pushes it in and out, `frequency` how many bumps per metre.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn fill_blob(
        &mut self,
        centre: Vector3,
        radii: Vector3,
        bumps: f32,
        frequency: f32,
        colour: Color,
        jitter: f32,
        seed: i64,
    ) {
        let s = seed as u32;
        self.with(|g, k| {
            g.fill_blob(
                v3(centre),
                v3(radii),
                bumps,
                frequency,
                s,
                Op::Fill(paint(colour, jitter * k, seed)),
            )
        });
    }

    #[func]
    fn carve_box(&mut self, min: Vector3, max: Vector3) {
        self.with(|g, _| g.fill_box(v3(min), v3(max), Op::Carve));
    }

    #[func]
    fn carve_ellipsoid(&mut self, centre: Vector3, radii: Vector3) {
        self.with(|g, _| g.fill_ellipsoid(v3(centre), v3(radii), Op::Carve));
    }

    #[func]
    fn carve_capsule(&mut self, a: Vector3, b: Vector3, ra: f32, rb: f32) {
        self.with(|g, _| g.fill_capsule(v3(a), v3(b), ra, rb, Op::Carve));
    }

    /// Recolours only cells that are already filled inside the box (markings, moss, dirt).
    #[func]
    fn paint_box(&mut self, min: Vector3, max: Vector3, colour: Color, jitter: f32, seed: i64) {
        self.with(|g, k| g.fill_box(v3(min), v3(max), Op::Paint(paint(colour, jitter * k, seed))));
    }

    #[func]
    fn paint_ellipsoid(
        &mut self,
        centre: Vector3,
        radii: Vector3,
        colour: Color,
        jitter: f32,
        seed: i64,
    ) {
        self.with(|g, k| {
            g.fill_ellipsoid(
                v3(centre),
                v3(radii),
                Op::Paint(paint(colour, jitter * k, seed)),
            )
        });
    }

    /// Scales the colour jitter of every fill after this call (0 = flat colours).
    #[func]
    fn set_jitter_scale(&mut self, scale: f32) {
        self.jitter_scale = scale.max(0.0);
    }

    #[func]
    fn voxel_count(&self) -> i64 {
        self.grid.as_ref().map_or(0, |g| g.filled() as i64)
    }

    #[func]
    fn cells(&self) -> Vector3i {
        self.grid.as_ref().map_or(Vector3i::ZERO, |g| {
            Vector3i::new(g.nx as i32, g.ny as i32, g.nz as i32)
        })
    }

    #[func]
    fn voxel_size(&self) -> f32 {
        self.grid.as_ref().map_or(0.0, |g| g.voxel)
    }

    /// Arrays for `ArrayMesh.add_surface_from_arrays` (vertex, normal, colour, index), or an
    /// empty array when nothing is filled.
    #[func]
    fn mesh_arrays(&self) -> VarArray {
        let Some(grid) = self.grid.as_ref() else {
            return VarArray::new();
        };
        arrays_of(&grid.mesh())
    }
}

impl VoxelModel {
    fn with(&mut self, f: impl FnOnce(&mut Grid, f32)) {
        let k = self.jitter_scale;
        if let Some(g) = self.grid.as_mut() {
            f(g, k);
        } else {
            godot_error!("VoxelModel: call setup() before filling");
        }
    }
}

fn v3(v: Vector3) -> [f32; 3] {
    [v.x, v.y, v.z]
}

fn paint(c: Color, jitter: f32, seed: i64) -> Paint {
    let ch = |v: f32| (v.clamp(0.0, 1.0) * 255.0).round() as u32;
    Paint {
        colour: (ch(c.r) << 16) | (ch(c.g) << 8) | ch(c.b),
        jitter: jitter.clamp(0.0, 1.0),
        seed: seed as u32,
    }
}

fn to_color(c: Colour) -> Color {
    let ch = |shift: u32| ((c >> shift) & 0xFF) as f32 / 255.0;
    Color::from_rgb(ch(16), ch(8), ch(0))
}

/// Arrays for `ArrayMesh.add_surface_from_arrays`, or empty when there is nothing to draw.
fn arrays_of(mesh: &Mesh) -> VarArray {
    if mesh.indices.is_empty() {
        return VarArray::new();
    }
    let vertices: PackedVector3Array = mesh
        .positions
        .iter()
        .map(|p| Vector3::new(p[0], p[1], p[2]))
        .collect();
    let normals: PackedVector3Array = mesh
        .normals
        .iter()
        .map(|n| Vector3::new(n[0], n[1], n[2]))
        .collect();
    let colours: PackedColorArray = mesh.colours.iter().map(|&c| to_color(c)).collect();
    let indices: PackedInt32Array = mesh.indices.iter().map(|&i| i as i32).collect();
    let mut arrays = VarArray::new();
    arrays.resize(ArrayType::MAX.ord() as usize, &Variant::nil());
    arrays.set(ArrayType::VERTEX.ord() as usize, &vertices.to_variant());
    arrays.set(ArrayType::NORMAL.ord() as usize, &normals.to_variant());
    arrays.set(ArrayType::COLOR.ord() as usize, &colours.to_variant());
    arrays.set(ArrayType::INDEX.ord() as usize, &indices.to_variant());
    arrays
}

fn colour_of(c: Color) -> Colour {
    paint(c, 0.0, 0).colour
}

/// Voxel ground tiles: `VoxelGround.tile_arrays(...)` turns coarse heights and colours over a
/// tile into blocky columns (see voxkit_core::heightfield). Stateless.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct VoxelGround {
    base: Base<RefCounted>,
}

#[godot_api]
impl VoxelGround {
    /// `heights` is `cn` x `cn` (row-major by z), `spacing` metres apart; `colours` is
    /// `cc` x `cc` over the same tile; the tile is `n` columns of `voxel` metres a side.
    /// Returns mesh arrays in tile-local metres.
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
        steep_slope: f32,
        steep: Color,
        side: Color,
        skirt: f32,
        seed: i64,
    ) -> VarArray {
        let (cn, cc, n) = (
            cn.max(2) as usize,
            cc.max(2) as usize,
            n.clamp(1, 1024) as usize,
        );
        if heights.len() < cn * cn || colours.len() < cc * cc {
            godot_error!("VoxelGround: heights or colours shorter than the grid");
            return VarArray::new();
        }
        let hs = heights.as_slice().to_vec();
        let cs: Vec<Colour> = colours.as_slice().iter().map(|&c| colour_of(c)).collect();
        let tile = Tile {
            heights: &hs,
            cn,
            spacing,
            colours: &cs,
            cc,
            n,
            voxel: voxel.max(0.01),
            steep_slope,
            steep: colour_of(steep),
            side: colour_of(side),
            skirt,
            seed: seed as u32,
        };
        arrays_of(&heightfield::mesh(&tile))
    }
}
