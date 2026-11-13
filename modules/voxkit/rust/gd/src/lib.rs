//! gdext binding for voxkit_core: GDScript gets `VoxelModel`, a grid generators fill with
//! shapes in metres and turn into an ArrayMesh.

// gdext's entry point must be an `unsafe impl` and its macro drops item-level allows, so
// binding crates allow unsafe at crate level. Pure crates keep it denied; keep logic there.
#![allow(unsafe_code)]

use godot::classes::mesh::ArrayType;
use godot::prelude::*;
use std::sync::RwLock;
use voxkit_core::heightfield::{self, Tile};
use voxkit_core::{Colour, Grid, Mesh, OPEN, Op, Paint};

/// Brightness per corner level (0 tucked in to 3 open) when corner shading is on, for every
/// mesh this extension makes. Set once from voxkit's data by `VoxelModel.set_corner_shading`.
static SHADING: RwLock<Option<[f32; 4]>> = RwLock::new(None);

fn shading() -> Option<[f32; 4]> {
    SHADING.read().map_or(None, |s| *s)
}

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

    /// The material index every fill after this call writes into its cells (see
    /// `VoxMaterials` for the names); 0 is "default".
    #[func]
    fn set_material(&mut self, index: i64) {
        self.with(|g, _| g.brush = index.clamp(0, 255) as u8);
    }

    /// Sets the material of the filled cells inside the box, leaving their colour.
    #[func]
    fn mark_box(&mut self, min: Vector3, max: Vector3, index: i64) {
        self.with(|g, _| g.fill_box(v3(min), v3(max), Op::Mark(index.clamp(0, 255) as u8)));
    }

    /// Material index of the cell holding `point` (model space); 0 for air and outside. A
    /// hit point lies on a face, so callers step half a voxel into the surface first.
    #[func]
    fn material_at(&self, point: Vector3) -> i64 {
        self.grid
            .as_ref()
            .map_or(0, |g| g.material_at(v3(point)) as i64)
    }

    /// Colour of the cell holding `point` (model space); fully transparent for air.
    #[func]
    fn colour_at(&self, point: Vector3) -> Color {
        match self.grid.as_ref().map(|g| g.colour_at(v3(point))) {
            Some(c) if c != voxkit_core::EMPTY => to_color(c),
            _ => Color::from_rgba(0.0, 0.0, 0.0, 0.0),
        }
    }

    /// The material most filled cells inside the box have (model space), 0 when none has
    /// one: a wall piece's main material.
    #[func]
    fn dominant_material(&self, min: Vector3, max: Vector3) -> i64 {
        self.grid
            .as_ref()
            .map_or(0, |g| g.dominant_material(v3(min), v3(max)) as i64)
    }

    /// Each connected patch of material `index`, as an `AABB` in model space, in the same
    /// order on every instance (panes of glass, numbered alike everywhere).
    #[func]
    fn components(&self, index: i64) -> Array<Aabb> {
        let mut out = Array::new();
        if let Some(g) = self.grid.as_ref() {
            for (min, max) in g.components(index.clamp(0, 255) as u8) {
                let lo = Vector3::new(min[0], min[1], min[2]);
                let hi = Vector3::new(max[0], max[1], max[2]);
                out.push(Aabb::new(lo, hi - lo));
            }
        }
        out
    }

    /// The connected patch of material `index` holding the cell at `point` (model space), as
    /// an `AABB`, or an empty `AABB` when that cell isn't that material or the patch is more
    /// than `cap` cells (a brick, not a wall).
    #[func]
    fn component_at(&self, point: Vector3, index: i64, cap: i64) -> Aabb {
        let found = self.grid.as_ref().and_then(|g| {
            g.component_at(v3(point), index.clamp(0, 255) as u8, cap.max(1) as usize)
        });
        match found {
            Some((min, max)) => {
                let lo = Vector3::new(min[0], min[1], min[2]);
                Aabb::new(lo, Vector3::new(max[0], max[1], max[2]) - lo)
            }
            None => Aabb::default(),
        }
    }

    /// How many filled cells of material `index` have their centres inside the box.
    #[func]
    fn count_material(&self, min: Vector3, max: Vector3, index: i64) -> i64 {
        self.grid.as_ref().map_or(0, |g| {
            g.count_material(v3(min), v3(max), index.clamp(0, 255) as u8) as i64
        })
    }

    /// Empties the cells of material `index` inside the box, leaving every other material.
    #[func]
    fn carve_material_box(&mut self, min: Vector3, max: Vector3, index: i64) {
        self.with(|g, _| {
            g.fill_box(
                v3(min),
                v3(max),
                Op::CarveMaterial(index.clamp(0, 255) as u8),
            )
        });
    }

    /// Recolours only the cells of material `index` inside the ellipsoid (a crack mark).
    #[func]
    fn recolour_ellipsoid(&mut self, centre: Vector3, radii: Vector3, colour: Color, index: i64) {
        self.with(|g, _| {
            g.fill_ellipsoid(
                v3(centre),
                v3(radii),
                Op::Recolour(paint(colour, 0.0, 0), index.clamp(0, 255) as u8),
            )
        });
    }

    /// Breaks the cells inside the box into fragments round `seeds` (model space), ragged by up
    /// to `jag` voxels; touching cells of material `unit` (bricks) stay together. Returns
    /// `[{model, offset, lo, hi}]` in seed order (seeds that got nothing are left out): each
    /// fragment as its own model, where its origin sits in this one, and its filled bounds.
    #[func]
    fn fracture(
        &self,
        min: Vector3,
        max: Vector3,
        seeds: PackedVector3Array,
        unit: i64,
        jag: f32,
        seed: i64,
    ) -> VarArray {
        let mut out = VarArray::new();
        let Some(grid) = self.grid.as_ref() else {
            return out;
        };
        let points: Vec<[f32; 3]> = seeds.as_slice().iter().map(|p| v3(*p)).collect();
        for f in grid.fracture(
            v3(min),
            v3(max),
            &points,
            unit.clamp(0, 255) as u8,
            jag,
            seed as u32,
        ) {
            let model = Gd::from_init_fn(|base| VoxelModel {
                base,
                grid: Some(f.grid),
                jitter_scale: self.jitter_scale,
            });
            let mut d = VarDictionary::new();
            d.set("model", &model);
            d.set(
                "offset",
                Vector3::new(f.offset[0], f.offset[1], f.offset[2]),
            );
            d.set("lo", Vector3::new(f.lo[0], f.lo[1], f.lo[2]));
            d.set("hi", Vector3::new(f.hi[0], f.hi[1], f.hi[2]));
            out.push(&d.to_variant());
        }
        out
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

    /// The cells packed for a GPU volume (see `voxkit_core::Atlas`): `{bricks: Vector3i,
    /// indirection: PackedByteArray (RGBA8 per brick), cells: Vector3i, atlas:
    /// PackedByteArray (RG8 per cell, 5-6-5 colour), used: int}`. Only bricks holding
    /// something are in the atlas, `per_row` bricks to a row and a column.
    #[func]
    fn brick_atlas(&self, brick: i64, per_row: i64) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(grid) = self.grid.as_ref() else {
            return out;
        };
        let a = grid.brick_atlas(brick.max(1) as usize, per_row.max(1) as usize);
        let v3 = |n: [usize; 3]| Vector3i::new(n[0] as i32, n[1] as i32, n[2] as i32);
        out.set("bricks", v3(a.bricks));
        out.set("indirection", &PackedByteArray::from(a.indirection));
        out.set("cells", v3(a.cells));
        out.set("atlas", &PackedByteArray::from(a.atlas));
        out.set("used", a.used as i64);
        out
    }

    /// Which `brick`-cell cubes hold anything, as one byte each (255 or 0) in `rgba_slices`
    /// order, for an R8 `ImageTexture3D` of `brick_counts(brick)` texels.
    #[func]
    fn brick_occupancy(&self, brick: i64) -> PackedByteArray {
        self.grid.as_ref().map_or(PackedByteArray::new(), |g| {
            PackedByteArray::from(g.brick_occupancy(brick.max(1) as usize).0)
        })
    }

    /// How many bricks of `brick` cells cover the grid on each axis.
    #[func]
    fn brick_counts(&self, brick: i64) -> Vector3i {
        self.grid.as_ref().map_or(Vector3i::ZERO, |g| {
            let b = brick.max(1) as usize;
            Vector3i::new(
                g.nx.div_ceil(b) as i32,
                g.ny.div_ceil(b) as i32,
                g.nz.div_ceil(b) as i32,
            )
        })
    }

    /// Whether cell (x, y, z) is filled; outside the grid is air.
    #[func]
    fn is_filled(&self, x: i64, y: i64, z: i64) -> bool {
        self.grid
            .as_ref()
            .is_some_and(|g| g.get(x, y, z) != voxkit_core::EMPTY)
    }

    /// The cells as RGBA8 bytes for an `ImageTexture3D`: `cells().z` slices of
    /// `cells().x` by `cells().y` pixels, one after another; air is transparent black.
    #[func]
    fn rgba_slices(&self) -> PackedByteArray {
        self.grid.as_ref().map_or(PackedByteArray::new(), |g| {
            PackedByteArray::from(g.rgba_slices())
        })
    }

    #[func]
    fn voxel_size(&self) -> f32 {
        self.grid.as_ref().map_or(0.0, |g| g.voxel)
    }

    /// Arrays for `ArrayMesh.add_surface_from_arrays` (vertex, normal, colour, index), or an
    /// empty array when nothing is filled.
    /// Like `mesh_arrays`, with no face longer than `max_run` cells along z, for meshes that
    /// get bent afterwards.
    #[func]
    fn mesh_arrays_bendable(&mut self, max_run: i64) -> VarArray {
        let Some(grid) = self.grid.as_mut() else {
            return VarArray::new();
        };
        grid.corners = shading().is_some();
        arrays_of(&grid.mesh_max_run(max_run.max(1) as usize))
    }

    #[func]
    fn mesh_arrays(&mut self) -> VarArray {
        let Some(grid) = self.grid.as_mut() else {
            return VarArray::new();
        };
        grid.corners = shading().is_some();
        arrays_of(&grid.mesh())
    }

    /// A copy of the cells inside the box `min..max` (model space) as its own model:
    /// `{model, offset}`, where `offset` is where the copy's origin sits in this model, so a
    /// mesh of it placed there lines up with the original (a falling piece of wall).
    #[func]
    fn copy_box(&self, min: Vector3, max: Vector3) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(grid) = self.grid.as_ref() else {
            return out;
        };
        let (copy, at) = grid.copy_box(v3(min), v3(max));
        let model = Gd::from_init_fn(|base| VoxelModel {
            base,
            grid: Some(copy),
            jitter_scale: self.jitter_scale,
        });
        out.set("model", &model);
        out.set("offset", Vector3::new(at[0], at[1], at[2]));
        out
    }

    /// Corner shading for every voxel mesh made from now on: `levels` holds the brightness
    /// of a face corner at each level (0 tucked into an inside corner, 3 open); empty turns
    /// it off.
    #[func]
    fn set_corner_shading(levels: PackedFloat32Array) {
        let l = levels.as_slice();
        let value = (l.len() == 4).then(|| [l[0], l[1], l[2], l[3]].map(|x| x.clamp(0.0, 1.0)));
        if let Ok(mut s) = SHADING.write() {
            *s = value;
        }
    }

    /// How many 16-cell chunks the model is split into.
    #[func]
    fn chunk_count(&self) -> i64 {
        self.grid.as_ref().map_or(0, |g| g.chunk_count() as i64)
    }

    /// Draws these materials see-through (glass): they leave the normal chunk meshes and come
    /// back in `remesh_dirty_layers` as each chunk's clear mesh. Every chunk is remeshed.
    #[func]
    fn set_clear_materials(&mut self, indices: PackedInt32Array) {
        self.with(|g, _| {
            for m in 1..=255u8 {
                g.set_clear(m, indices.as_slice().contains(&(m as i32)));
            }
        });
    }

    /// Like `remesh_dirty`, with both layers: `{chunk id: [arrays, clear arrays]}` (empty arrays
    /// where a layer has nothing to draw).
    #[func]
    fn remesh_dirty_layers(&mut self) -> VarDictionary {
        let mut out = VarDictionary::new();
        if let Some(grid) = self.grid.as_mut() {
            grid.corners = shading().is_some();
            for (id, mesh, clear) in grid.remesh_dirty_layers() {
                let mut pair = VarArray::new();
                pair.push(&arrays_of(&mesh).to_variant());
                pair.push(&arrays_of(&clear).to_variant());
                out.set(id as i64, &pair);
            }
        }
        out
    }

    /// Meshes every chunk changed since the last call (all of them the first time) and marks
    /// them clean: `{chunk id: arrays}`, empty arrays where a chunk has nothing to draw.
    #[func]
    fn remesh_dirty(&mut self) -> VarDictionary {
        let mut out = VarDictionary::new();
        if let Some(grid) = self.grid.as_mut() {
            grid.corners = shading().is_some();
            for (id, mesh) in grid.remesh_dirty() {
                out.set(id as i64, &arrays_of(&mesh));
            }
        }
        out
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
    let levels = shading().unwrap_or([1.0; 4]);
    let colours: PackedColorArray = mesh
        .colours
        .iter()
        .zip(mesh.shade.iter().chain(std::iter::repeat(&OPEN)))
        .map(|(&c, &l)| {
            let k = levels[usize::from(l.min(OPEN))];
            let col = to_color(c);
            Color::from_rgba(col.r * k, col.g * k, col.b * k, col.a)
        })
        .collect();
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
            corners: shading().is_some(),
        };
        arrays_of(&heightfield::mesh(&tile))
    }
}
