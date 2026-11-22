//! Voxel ground: a tile of ground heights turned into columns `voxel` metres square. Heights
//! and colours come in on a coarse grid and are filled in per column here, so the caller only
//! samples a few hundred points per tile.
//!
//! A column on gentle ground (rise over run under `tilt_grade`) tilts its top to the true
//! height at its four corners. Tilted neighbours share those corners, so they meet with no
//! wall. Steeper columns keep flat tops stepping in whole voxels, so banks, cliffs and crater
//! walls read as blocks. Wherever two columns show different heights along their shared edge
//! a wall closes the gap, facing the lower side.
//!
//! Beside a road or track strip (a model of its own) the ground tilts to meet its edge and
//! stays just under it; lanes are painted into the columns (see `ways`). Where ground that
//! tilts meets ground that steps, a step standing over the tilted edge is rounded up, so the
//! two meet in a riser rather than a crevice.

use std::ops::Range;

use crate::ways::{self, Column, Look, Ways};
use crate::{Colour, Mesh, OPEN, corner_level, hash};

pub struct Tile<'a> {
    /// Heights on a `cn` x `cn` grid covering the tile, `spacing` metres apart, row-major
    /// by z then x.
    pub heights: &'a [f32],
    pub cn: usize,
    pub spacing: f32,
    /// Ground colours on a `cc` x `cc` grid over the same tile.
    pub colours: &'a [Colour],
    pub cc: usize,
    /// Columns per side, and their size in metres.
    pub n: usize,
    pub voxel: f32,
    /// Ground steeper than this (rise over run) shows `steep` instead of its colour.
    pub steep_slope: f32,
    pub steep: Colour,
    /// Colour of the sides of columns (soil under the grass).
    pub side: Colour,
    /// How far the outer walls of the tile reach down, hiding cracks to the next tile.
    pub skirt: f32,
    pub seed: u32,
    /// Darken top-face corners next to higher columns (see `crate::corner_level`).
    pub corners: bool,
    /// Columns gentler than this (rise over run) tilt their tops; 0 keeps every column
    /// stepped.
    pub tilt_grade: f32,
    /// Columns within `band` metres of a strip's edge, or `pad_band` of a levelled pad's,
    /// tilt to meet it when gentler than `band_grade`; a steeper bank keeps its steps.
    pub band: f32,
    pub pad_band: f32,
    pub band_grade: f32,
    /// Ways over the tile, `ways::WAY_STRIDE` floats each, in tile-local metres.
    pub ways: &'a [f32],
    pub look: Look,
    /// Per height sample, non-zero where a crater has been dug (empty when none has): ways
    /// leave the earth there unpainted.
    pub dug: &'a [u8],
}

impl Tile<'_> {
    fn size(&self) -> f32 {
        self.n as f32 * self.voxel
    }

    fn sample(&self, x: f32, z: f32) -> f32 {
        let last = (self.cn - 1) as f32;
        let fx = (x / self.spacing).clamp(0.0, last);
        let fz = (z / self.spacing).clamp(0.0, last);
        let (ix, iz) = (fx as usize, fz as usize);
        let (jx, jz) = ((ix + 1).min(self.cn - 1), (iz + 1).min(self.cn - 1));
        let (tx, tz) = (fx - ix as f32, fz - iz as f32);
        let h = |x: usize, z: usize| self.heights[z * self.cn + x];
        let a = h(ix, iz) + (h(jx, iz) - h(ix, iz)) * tx;
        let b = h(ix, jz) + (h(jx, jz) - h(ix, jz)) * tx;
        a + (b - a) * tz
    }

    /// Whether a crater was dug at the height sample nearest (x, z).
    fn dug_at(&self, x: f32, z: f32) -> bool {
        if self.dug.len() < self.cn * self.cn {
            return false;
        }
        let last = (self.cn - 1) as f32;
        let ix = (x / self.spacing).round().clamp(0.0, last) as usize;
        let iz = (z / self.spacing).round().clamp(0.0, last) as usize;
        self.dug[iz * self.cn + ix] != 0
    }

    /// A column's colour: one of the four nearest coarse colours, picked with their
    /// bilinear weights by a per-column hash, so biomes blend as a dither of voxels and
    /// large plain areas still merge into big faces.
    fn colour(&self, x: f32, z: f32, a: usize, b: usize) -> Colour {
        let cell = self.size() / (self.cc - 1) as f32;
        let last = (self.cc - 1) as f32;
        let fx = (x / cell).clamp(0.0, last);
        let fz = (z / cell).clamp(0.0, last);
        let (ix, iz) = (fx as usize, fz as usize);
        let (jx, jz) = ((ix + 1).min(self.cc - 1), (iz + 1).min(self.cc - 1));
        let (tx, tz) = (fx - ix as f32, fz - iz as f32);
        let r = hash(a as u32, b as u32, 7, self.seed);
        let pick_x = if hash(a as u32, b as u32, 11, self.seed) < tx {
            jx
        } else {
            ix
        };
        let pick_z = if r < tz { jz } else { iz };
        self.colours[pick_z * self.cc + pick_x]
    }
}

/// The ground's shape per column: stepped tops (in voxels), the true height at every grid
/// corner, and which columns tilt to those corners.
struct Shape {
    tops: Vec<i32>,
    corner: Vec<f32>,
    tilted: Vec<bool>,
    /// Tilted with four equal corners: drawn with the steps, merged in two directions.
    flat: Vec<bool>,
    /// Painted by a way: drawn with the way's own fine grain (see `PAINTED`).
    painted: Vec<bool>,
}

/// Set in a top vertex's shade byte (over its 0 to 3 level) where a way painted its column,
/// so the ground's shader draws it with the strip model's finer grain.
pub const PAINTED: u8 = 4;

impl Shape {
    fn corner(&self, n: usize, a: usize, b: usize) -> f32 {
        self.corner[b * (n + 1) + a]
    }

    /// The heights column `i` shows at grid corners `c0` and `c1`: a tilted top its corners,
    /// a step its level.
    fn edge(&self, i: usize, c0: usize, c1: usize, v: f32) -> [f32; 2] {
        if self.tilted[i] {
            [self.corner[c0], self.corner[c1]]
        } else {
            [self.tops[i] as f32 * v; 2]
        }
    }
}

/// Builds the tile's mesh in tile-local metres (x and z from 0 to `n * voxel`, y as given).
pub fn mesh(t: &Tile) -> Mesh {
    mesh_marked(t).0
}

/// `mesh`, and the range of its vertices that belong to sloping tilted tops (the shader
/// varies them per column, not per layer).
pub fn mesh_marked(t: &Tile) -> (Mesh, Range<usize>) {
    let (tops, centre, mut colours) = columns(t);
    let shape = shape(t, tops, &centre, &mut colours);
    let mut out = Mesh::default();
    let steps = plan_steps(t, &shape, &colours);
    let slopes = plan_tilted(t, &shape, &colours);
    // Every block's corners: a block whose edge passes one gets a vertex there.
    let n1 = t.n + 1;
    let mut corners = vec![false; n1 * n1];
    for top in steps.iter().chain(&slopes) {
        let [a, b, w, h] = top.block;
        for (ca, cb) in [(a, b), (a + w, b), (a, b + h), (a + w, b + h)] {
            corners[cb * n1 + ca] = true;
        }
    }
    for top in &steps {
        push_top(&mut out, t, &shape, top, &corners);
    }
    let from = out.positions.len();
    for top in &slopes {
        push_top(&mut out, t, &shape, top, &corners);
    }
    let tilted = from..out.positions.len();
    push_walls(&mut out, t, &shape, &colours);
    (out, tilted)
}

/// Each column's top (in voxels), the height at its middle, and its colour.
fn columns(t: &Tile) -> (Vec<i32>, Vec<f32>, Vec<Colour>) {
    let (n, v) = (t.n, t.voxel);
    let mut tops = vec![0i32; n * n];
    let mut centre = vec![0f32; n * n];
    let mut colours = vec![0u32; n * n];
    for b in 0..n {
        for a in 0..n {
            let (x, z) = ((a as f32 + 0.5) * v, (b as f32 + 0.5) * v);
            let h = t.sample(x, z);
            centre[b * n + a] = h;
            // Down, never up: the visible top never stands above the smooth ground players
            // walk on, so nothing (the road, a tree's foot) is buried by a rounded-up step.
            tops[b * n + a] = (h / v).floor() as i32;
            let dx = t.sample(x + v, z) - t.sample(x - v, z);
            let dz = t.sample(x, z + v) - t.sample(x, z - v);
            let steep = (dx * dx + dz * dz).sqrt() / (2.0 * v) > t.steep_slope;
            colours[b * n + a] = if steep { t.steep } else { t.colour(x, z, a, b) };
        }
    }
    (tops, centre, colours)
}

/// Corner heights (held under strips), which columns tilt, and the colours ways paint.
fn shape(t: &Tile, mut tops: Vec<i32>, centre: &[f32], colours: &mut [Colour]) -> Shape {
    let (n, v) = (t.n, t.voxel);
    let n1 = n + 1;
    let mut corner: Vec<f32> = (0..n1 * n1)
        .map(|i| t.sample((i % n1) as f32 * v, (i / n1) as f32 * v))
        .collect();
    let paint_reach = v + t.look.track_fray.max(t.look.yard_fray);
    let mut ways = Ways::new(
        t.ways,
        t.band.max(paint_reach) + v,
        t.pad_band + v,
        t.size(),
        t.look.yard_round,
    );
    ways.voxel = v;
    if !ways.is_empty() {
        for (i, h) in corner.iter_mut().enumerate() {
            let (x, z) = ((i % n1) as f32 * v, (i / n1) as f32 * v);
            let held = ways.scan(&t.look, x, z, ways::HOLD).held(*h);
            // A crater keeps its depth: the frayed edge never fills it back in.
            if held < *h || !t.dug_at(x, z) {
                *h = held;
            }
        }
    }
    let mut tilted = vec![false; n * n];
    let mut painted = vec![false; n * n];
    for b in 0..n {
        for a in 0..n {
            let i = b * n + a;
            let c = |da: usize, db: usize| corner[(b + db) * n1 + a + da];
            let gx = (c(1, 0) + c(1, 1) - c(0, 0) - c(0, 1)) / (2.0 * v);
            let gz = (c(0, 1) + c(1, 1) - c(0, 0) - c(1, 0)) / (2.0 * v);
            let grade = (gx * gx + gz * gz).sqrt();
            let mut tilt = grade < t.tilt_grade;
            if !ways.is_empty() {
                let (x, z) = ((a as f32 + 0.5) * v, (b as f32 + 0.5) * v);
                let scan = ways.scan(&t.look, x, z, ways::HOLD);
                let gentle = grade < t.band_grade;
                // Under a strip always, so it can be held below it; beside it to meet its
                // edge, unless the bank is steep enough to read as steps.
                tilt |= scan
                    .strip
                    .is_some_and(|r| r.edge < 0.0 || (r.edge < t.band && gentle));
                tilt |= scan.lane.is_some_and(|r| r.edge < paint_reach && gentle);
                tilt |= scan.pad.is_some_and(|r| r.edge < t.pad_band && gentle);
                if let Some(r) = scan.paint().filter(|r| r.edge < paint_reach) {
                    let col = Column {
                        a,
                        b,
                        voxel: v,
                        ground: colours[i],
                        dug: t.dug_at(x, z),
                        seed: t.seed,
                    };
                    if let Some(paint) = ways::colour(&t.look, &r, &col) {
                        colours[i] = paint;
                        painted[i] = true;
                    }
                }
            }
            tilted[i] = tilt;
        }
    }
    // A step beside tilted ground whose middle stands over the tilted edge they share is
    // rounded up: rounded down it would sit below that edge, a dark crevice along the slope.
    let rounded: Vec<i32> = (0..n * n)
        .map(|i| {
            if tilted[i] {
                return tops[i];
            }
            let (a, b) = (i % n, i / n);
            let c = |ca: usize, cb: usize| corner[cb * n1 + ca];
            let mut edges: Vec<f32> = Vec::new();
            if a > 0 && tilted[i - 1] {
                edges.push(c(a, b).max(c(a, b + 1)));
            }
            if a + 1 < n && tilted[i + 1] {
                edges.push(c(a + 1, b).max(c(a + 1, b + 1)));
            }
            if b > 0 && tilted[i - n] {
                edges.push(c(a, b).max(c(a + 1, b)));
            }
            if b + 1 < n && tilted[i + n] {
                edges.push(c(a, b + 1).max(c(a + 1, b + 1)));
            }
            let over = edges
                .iter()
                .any(|&e| centre[i] >= e && (tops[i] as f32 * v) < e - 1e-4);
            if over {
                (centre[i] / v).ceil() as i32
            } else {
                tops[i]
            }
        })
        .collect();
    tops = rounded;
    let flat = (0..n * n)
        .map(|i| {
            let (a, b) = (i % n, i / n);
            let c = |ca: usize, cb: usize| corner[cb * n1 + ca].to_bits();
            tilted[i]
                && c(a, b) == c(a + 1, b)
                && c(a, b) == c(a, b + 1)
                && c(a, b) == c(a + 1, b + 1)
        })
        .collect();
    Shape {
        tops,
        corner,
        tilted,
        flat,
        painted,
    }
}

/// A top over a block of columns `[a, b, w, h]`.
struct Top {
    block: [usize; 4],
    colour: Colour,
    levels: [u8; 4],
    kind: TopKind,
    painted: bool,
}

#[derive(Clone, Copy, PartialEq)]
enum TopKind {
    /// A stepped top at this height.
    Step(f32),
    /// Tilted ground that is level.
    Level,
    /// Tilted ground that slopes.
    Slope,
}

/// Flat tops (stepped columns, and tilted ones on level ground), merged greedily by height,
/// colour and corner shading.
fn plan_steps(t: &Tile, s: &Shape, colours: &[Colour]) -> Vec<Top> {
    let mut out = Vec::new();
    let (n, v) = (t.n, t.voxel);
    let mut levels = if t.corners {
        step_levels(t, s)
    } else {
        vec![[OPEN; 4]; n * n]
    };
    for i in (0..n * n).filter(|&i| s.flat[i]) {
        levels[i] = tilt_levels(t, s, i % n, i / n);
    }
    let height = |i: usize| {
        if s.flat[i] {
            s.corner(n, i % n, i / n)
        } else {
            s.tops[i] as f32 * v
        }
    };
    let key = |i: usize| (height(i).to_bits(), colours[i], levels[i], s.painted[i]);
    let mut done: Vec<bool> = (0..n * n).map(|i| s.tilted[i] && !s.flat[i]).collect();
    for b in 0..n {
        for a in 0..n {
            let i = b * n + a;
            if done[i] {
                continue;
            }
            let same = |j: usize| !done[j] && key(j) == key(i);
            let mut w = 1;
            while a + w < n && same(i + w) {
                w += 1;
            }
            let mut h = 1;
            while b + h < n && (0..w).all(|k| same((b + h) * n + a + k)) {
                h += 1;
            }
            for j in (0..h).flat_map(|bb| (0..w).map(move |k| (b + bb) * n + a + k)) {
                done[j] = true;
            }
            out.push(Top {
                block: [a, b, w, h],
                colour: colours[i],
                levels: levels[i],
                kind: if s.flat[i] {
                    TopKind::Level
                } else {
                    TopKind::Step(height(i))
                },
                painted: s.painted[i],
            });
        }
    }
    out
}

/// How open each stepped top's four corners are: a neighbour is in the layer above when it
/// stands higher (a tilted one by its lowest corner). Columns one past each edge are
/// sampled, so corners at the tile's edge see their neighbours.
fn step_levels(t: &Tile, s: &Shape) -> Vec<[u8; 4]> {
    let (n, v) = (t.n, t.voxel);
    let level = |i: usize| -> i32 {
        if s.tilted[i] {
            let (a, b) = (i % n, i / n);
            let lo = [(0, 0), (1, 0), (0, 1), (1, 1)]
                .map(|(da, db)| s.corner(n, a + da, b + db))
                .into_iter()
                .fold(f32::INFINITY, f32::min);
            (lo / v).floor() as i32
        } else {
            s.tops[i]
        }
    };
    let top_at = |a: i64, b: i64| -> i32 {
        if (0..n as i64).contains(&a) && (0..n as i64).contains(&b) {
            level(b as usize * n + a as usize)
        } else {
            (t.sample((a as f32 + 0.5) * v, (b as f32 + 0.5) * v) / v).floor() as i32
        }
    };
    (0..n * n)
        .map(|i| {
            if s.tilted[i] {
                return [OPEN; 4];
            }
            let (a, b) = ((i % n) as i64, (i / n) as i64);
            let up = |da: i64, db: i64| top_at(a + da, b + db) > s.tops[i];
            [(-1, -1), (1, -1), (1, 1), (-1, 1)]
                .map(|(da, db): (i64, i64)| corner_level(up(da, 0), up(0, db), up(da, db)))
        })
        .collect()
}

/// How open each tilted top's corners are: a stepped neighbour standing over the corner by
/// half a voxel or more crowds it, as a higher column crowds a step's corner. Tilted
/// neighbours share the corner's height and never do.
fn tilt_levels(t: &Tile, s: &Shape, a: usize, b: usize) -> [u8; 4] {
    let (n, v) = (t.n, t.voxel);
    if !t.corners {
        return [OPEN; 4];
    }
    let over = |ca: i64, cb: i64, h: f32| -> bool {
        if !(0..n as i64).contains(&ca) || !(0..n as i64).contains(&cb) {
            // Past the tile's edge, sampled as `step_levels` does: a step if its ground is
            // too steep to tilt.
            let (x0, z0) = (ca as f32 * v, cb as f32 * v);
            let c = |dx: f32, dz: f32| t.sample(x0 + dx * v, z0 + dz * v);
            let gx = (c(1.0, 0.0) + c(1.0, 1.0) - c(0.0, 0.0) - c(0.0, 1.0)) / (2.0 * v);
            let gz = (c(0.0, 1.0) + c(1.0, 1.0) - c(0.0, 0.0) - c(1.0, 0.0)) / (2.0 * v);
            let top = (c(0.5, 0.5) / v).floor() * v;
            return (gx * gx + gz * gz).sqrt() >= t.tilt_grade && top >= h + v * 0.5;
        }
        let j = cb as usize * n + ca as usize;
        !s.tilted[j] && s.tops[j] as f32 * v >= h + v * 0.5
    };
    let (a, b) = (a as i64, b as i64);
    [(-1, -1), (1, -1), (1, 1), (-1, 1)].map(|(da, db): (i64, i64)| {
        let h = s.corner(
            n,
            (a + i64::from(da > 0)) as usize,
            (b + i64::from(db > 0)) as usize,
        );
        corner_level(
            over(a + da, b, h),
            over(a, b + db, h),
            over(a + da, b + db, h),
        )
    })
}

/// Sloping tilted tops. Unshaded ones of one colour merge into rectangles inside one coarse
/// sample cell, while every corner they cover still lies on the rectangle's bilinear
/// surface (corners held under a strip do not): its edges are then straight lines through
/// the corners its neighbours share, so nothing opens up between them.
fn plan_tilted(t: &Tile, s: &Shape, colours: &[Colour]) -> Vec<Top> {
    let mut out = Vec::new();
    let (n, v) = (t.n, t.voxel);
    let per_cell = ((t.spacing / v).round() as usize).max(1);
    let c = |ca: usize, cb: usize| s.corner(n, ca, cb);
    let sloping = |i: usize| s.tilted[i] && !s.flat[i];
    let levels: Vec<[u8; 4]> = (0..n * n)
        .map(|i| {
            if sloping(i) {
                tilt_levels(t, s, i % n, i / n)
            } else {
                [OPEN; 4]
            }
        })
        .collect();
    // Every corner of the w x h block at (a, b) on the bilinear surface of its four corners.
    let bilinear = |a: usize, b: usize, w: usize, h: usize| {
        let (c00, c10, c01, c11) = (c(a, b), c(a + w, b), c(a, b + h), c(a + w, b + h));
        (0..=h).all(|db| {
            (0..=w).all(|da| {
                let (u, q) = (da as f32 / w as f32, db as f32 / h as f32);
                let lo = c00 + (c10 - c00) * u;
                let hi = c01 + (c11 - c01) * u;
                (c(a + da, b + db) - (lo + (hi - lo) * q)).abs() < 1e-4
            })
        })
    };
    let mut done = vec![false; n * n];
    for b in 0..n {
        for a in 0..n {
            let i = b * n + a;
            if !sloping(i) || done[i] {
                continue;
            }
            let joins = |j: usize| {
                sloping(j)
                    && !done[j]
                    && colours[j] == colours[i]
                    && s.painted[j] == s.painted[i]
                    && levels[j] == [OPEN; 4]
            };
            let (mut w, mut h) = (1, 1);
            if levels[i] == [OPEN; 4] {
                while a + w < n
                    && (a + w) / per_cell == a / per_cell
                    && joins(i + w)
                    && bilinear(a, b, w + 1, 1)
                {
                    w += 1;
                }
                while b + h < n
                    && (b + h) / per_cell == b / per_cell
                    && (0..w).all(|k| joins((b + h) * n + a + k))
                    && bilinear(a, b, w, h + 1)
                {
                    h += 1;
                }
            }
            for j in (0..h).flat_map(|bb| (0..w).map(move |k| (b + bb) * n + a + k)) {
                done[j] = true;
            }
            out.push(Top {
                block: [a, b, w, h],
                colour: colours[i],
                levels: levels[i],
                kind: TopKind::Slope,
                painted: s.painted[i],
            });
        }
    }
    out
}

/// Draws `top`: a step as one quad, level and sloping tilted ground through `push_block`
/// (unless shaded: shaded level ground keeps the quad its shading was merged for).
fn push_top(out: &mut Mesh, t: &Tile, s: &Shape, top: &Top, corners: &[bool]) {
    let from = out.shade.len();
    push_top_plain(out, t, s, top, corners);
    if top.painted {
        for level in &mut out.shade[from..] {
            *level |= PAINTED;
        }
    }
}

fn push_top_plain(out: &mut Mesh, t: &Tile, s: &Shape, top: &Top, corners: &[bool]) {
    let v = t.voxel;
    let [a, b, w, h] = top.block;
    match top.kind {
        TopKind::Slope => push_block(out, t, s, top, true, corners),
        TopKind::Level if top.levels == [OPEN; 4] => push_block(out, t, s, top, false, corners),
        TopKind::Level | TopKind::Step(_) => {
            let y = match top.kind {
                TopKind::Step(y) => y,
                _ => s.corner(t.n, a, b),
            };
            out.push_quad(
                [a as f32 * v, y, b as f32 * v],
                [w as f32 * v, 0.0, 0.0],
                [0.0, 0.0, h as f32 * v],
                [0.0, 1.0, 0.0],
                top.colour,
                top.levels,
                true,
            );
        }
    }
}

/// A tilted top over its block of columns, with a vertex at every grid corner on its edge
/// that another block has a corner at, so no neighbour's corner meets it mid-edge (a
/// T-junction there opens hairline cracks when drawn). A block nothing meets mid-edge is a
/// quad, split as `Mesh::push_quad` splits it for its shading; one that something does
/// (always unshaded) fans out from its middle. With `smooth` each vertex takes the ground's
/// slope at its corner, so light runs evenly over a slope instead of changing at every quad.
fn push_block(out: &mut Mesh, t: &Tile, s: &Shape, top: &Top, smooth: bool, corners: &[bool]) {
    let (n, v) = (t.n, t.voxel);
    let n1 = n + 1;
    let [a, b, w, h] = top.block;
    let (colour, levels) = (top.colour, top.levels);
    let c = |ca: usize, cb: usize| s.corner(n, ca, cb);
    let normal = |ca: usize, cb: usize| -> [f32; 3] {
        if !smooth {
            return [0.0, 1.0, 0.0];
        }
        let (l, r) = (ca.saturating_sub(1), (ca + 1).min(n));
        let (d, u) = (cb.saturating_sub(1), (cb + 1).min(n));
        let gx = (c(r, cb) - c(l, cb)) / ((r - l) as f32 * v);
        let gz = (c(ca, u) - c(ca, d)) / ((u - d) as f32 * v);
        let len = (gx * gx + gz * gz + 1.0).sqrt();
        [-gx / len, 1.0 / len, -gz / len]
    };
    let point = |ca: usize, cb: usize| [ca as f32 * v, c(ca, cb), cb as f32 * v];
    let base = out.positions.len() as u32;
    let mut push = |p: [f32; 3], nrm: [f32; 3], level: u8| {
        out.positions.push(p);
        out.normals.push(nrm);
        out.colours.push(colour);
        out.shade.push(level);
    };
    // Round from (a, b) along x first: seen from above the same turn as a quad from
    // `Mesh::push_quad`, so the fan faces up.
    let ring: Vec<(usize, usize)> = (0..w)
        .map(|k| (a + k, b))
        .chain((0..h).map(|k| (a + w, b + k)))
        .chain((0..w).map(|k| (a + w - k, b + h)))
        .chain((0..h).map(|k| (a, b + h - k)))
        .filter(|&(ca, cb)| {
            let own = (ca == a || ca == a + w) && (cb == b || cb == b + h);
            own || corners[cb * n1 + ca]
        })
        .collect();
    if ring.len() == 4 {
        for (k, (ca, cb)) in [(a, b), (a + w, b), (a + w, b + h), (a, b + h)]
            .into_iter()
            .enumerate()
        {
            push(point(ca, cb), normal(ca, cb), levels[k]);
        }
        let flip = u32::from(levels[0]) + u32::from(levels[2])
            < u32::from(levels[1]) + u32::from(levels[3]);
        let tris: [u32; 6] = if flip {
            [0, 1, 3, 1, 2, 3]
        } else {
            [0, 1, 2, 0, 2, 3]
        };
        out.indices.extend(tris.iter().map(|k| base + k));
        return;
    }
    let mid = [
        (a as f32 + w as f32 / 2.0) * v,
        (c(a, b) + c(a + w, b) + c(a, b + h) + c(a + w, b + h)) / 4.0,
        (b as f32 + h as f32 / 2.0) * v,
    ];
    let mid_normal = if smooth {
        let gx = (c(a + w, b) + c(a + w, b + h) - c(a, b) - c(a, b + h)) / (2.0 * w as f32 * v);
        let gz = (c(a, b + h) + c(a + w, b + h) - c(a, b) - c(a + w, b)) / (2.0 * h as f32 * v);
        let len = (gx * gx + gz * gz + 1.0).sqrt();
        [-gx / len, 1.0 / len, -gz / len]
    } else {
        [0.0, 1.0, 0.0]
    };
    push(mid, mid_normal, OPEN);
    for &(ca, cb) in &ring {
        push(point(ca, cb), normal(ca, cb), OPEN);
    }
    let m = ring.len() as u32;
    for k in 0..m {
        out.indices
            .extend([base, base + 1 + k, base + 1 + (k + 1) % m]);
    }
}

/// Walls between neighbours that show different heights along their shared edge, and the
/// skirts down the tile's outer edges.
fn push_walls(out: &mut Mesh, t: &Tile, s: &Shape, colours: &[Colour]) {
    let (n, v) = (t.n, t.voxel);
    let n1 = n + 1;
    let skirt = (t.skirt / v).ceil() * v;
    for b in 0..n {
        for a in 0..n {
            let i = b * n + a;
            let (x0, x1, z0, z1) = (
                a as f32 * v,
                (a + 1) as f32 * v,
                b as f32 * v,
                (b + 1) as f32 * v,
            );
            let (c00, c10, c01, c11) = (
                b * n1 + a,
                b * n1 + a + 1,
                (b + 1) * n1 + a,
                (b + 1) * n1 + a + 1,
            );
            // To the +x and +z neighbours, once per shared edge.
            if a + 1 < n {
                let j = i + 1;
                let e = Edge {
                    p0: [x1, z0],
                    p1: [x1, z1],
                    toward_b: [1.0, 0.0, 0.0],
                };
                wall(
                    out,
                    t,
                    &e,
                    [s.edge(i, c10, c11, v), s.edge(j, c10, c11, v)],
                    [colours[i], colours[j]],
                );
            }
            if b + 1 < n {
                let j = i + n;
                let e = Edge {
                    p0: [x0, z1],
                    p1: [x1, z1],
                    toward_b: [0.0, 0.0, 1.0],
                };
                wall(
                    out,
                    t,
                    &e,
                    [s.edge(i, c01, c11, v), s.edge(j, c01, c11, v)],
                    [colours[i], colours[j]],
                );
            }
            // Skirts hide cracks to a neighbouring tile of another detail.
            let mut skirt_at = |p0: [f32; 2], p1: [f32; 2], h: [f32; 2], normal: [f32; 3]| {
                let low = h[0].min(h[1]) - skirt;
                push_poly(
                    out,
                    &[
                        [p0[0], low, p0[1]],
                        [p1[0], low, p1[1]],
                        [p1[0], h[1], p1[1]],
                        [p0[0], h[0], p0[1]],
                    ],
                    Some(normal),
                    t.side,
                    [OPEN; 4],
                );
            };
            if a == 0 {
                skirt_at([x0, z0], [x0, z1], s.edge(i, c00, c01, v), [-1.0, 0.0, 0.0]);
            }
            if a + 1 == n {
                skirt_at([x1, z0], [x1, z1], s.edge(i, c10, c11, v), [1.0, 0.0, 0.0]);
            }
            if b == 0 {
                skirt_at([x0, z0], [x1, z0], s.edge(i, c00, c10, v), [0.0, 0.0, -1.0]);
            }
            if b + 1 == n {
                skirt_at([x0, z1], [x1, z1], s.edge(i, c01, c11, v), [0.0, 0.0, 1.0]);
            }
        }
    }
}

/// A shared edge from `p0` to `p1` (x, z) between column A and column B, `toward_b` pointing
/// from A to B.
struct Edge {
    p0: [f32; 2],
    p1: [f32; 2],
    toward_b: [f32; 3],
}

/// The wall along `e` where A shows heights `h[0]` and B `h[1]` (at p0, p1). Each part faces
/// the lower side; profiles that cross split into two triangles.
fn wall(out: &mut Mesh, t: &Tile, e: &Edge, h: [[f32; 2]; 2], c: [Colour; 2]) {
    let (ha, mut hb) = (h[0], h[1]);
    // Ends that differ by a hair meet: a wall pinched to nothing there, not a sliver
    // twisted the wrong way.
    for k in 0..2 {
        if (ha[k] - hb[k]).abs() < 1e-4 {
            hb[k] = ha[k];
        }
    }
    let (d0, d1) = (ha[0] - hb[0], ha[1] - hb[1]);
    if d0 == 0.0 && d1 == 0.0 {
        return;
    }
    let (p0, p1, toward_b) = (e.p0, e.p1, e.toward_b);
    let back = toward_b.map(|x| -x);
    // Small steps are the ground's own colour in shade; only real walls show soil, or every
    // gentle slope would read brown from a distance.
    let colour = |higher: Colour, step: f32| {
        if step <= 2.0 * t.voxel + 1e-4 {
            shade(higher)
        } else {
            t.side
        }
    };
    let at = |p: [f32; 2], y: f32| [p[0], y, p[1]];
    if d0 >= 0.0 && d1 >= 0.0 {
        push_poly(
            out,
            &[at(p0, hb[0]), at(p1, hb[1]), at(p1, ha[1]), at(p0, ha[0])],
            Some(toward_b),
            colour(c[0], d0.max(d1)),
            [OPEN; 4],
        );
    } else if d0 <= 0.0 && d1 <= 0.0 {
        push_poly(
            out,
            &[at(p0, ha[0]), at(p1, ha[1]), at(p1, hb[1]), at(p0, hb[0])],
            Some(back),
            colour(c[1], (-d0).max(-d1)),
            [OPEN; 4],
        );
    } else {
        let k = d0 / (d0 - d1);
        let ps = [p0[0] + (p1[0] - p0[0]) * k, p0[1] + (p1[1] - p0[1]) * k];
        let hs = ha[0] + (ha[1] - ha[0]) * k;
        let (n0, c0) = if d0 > 0.0 {
            (toward_b, colour(c[0], d0))
        } else {
            (back, colour(c[1], -d0))
        };
        let (n1, c1) = if d1 > 0.0 {
            (toward_b, colour(c[0], d1))
        } else {
            (back, colour(c[1], -d1))
        };
        push_poly(
            out,
            &[at(p0, ha[0]), at(p0, hb[0]), at(ps, hs)],
            Some(n0),
            c0,
            [OPEN; 4],
        );
        push_poly(
            out,
            &[at(p1, ha[1]), at(p1, hb[1]), at(ps, hs)],
            Some(n1),
            c1,
            [OPEN; 4],
        );
    }
}

fn shade(c: Colour) -> Colour {
    let ch = |shift: u32| (((c >> shift) & 0xFF) as f32 * 0.72) as u32;
    (ch(16) << 16) | (ch(8) << 8) | ch(0)
}

/// A triangle or quad facing `normal`; with None it faces up and its normal is the polygon's
/// own (a tilted top). `levels` shade a quad's corners as `Mesh::push_quad`'s do.
fn push_poly(
    out: &mut Mesh,
    pts: &[[f32; 3]],
    normal: Option<[f32; 3]>,
    colour: Colour,
    levels: [u8; 4],
) {
    // A wall pinched to nothing at one end has two equal corners there: drawn as the
    // triangle it is, with no zero-area half.
    let mut kept: Vec<([f32; 3], u8)> = Vec::with_capacity(4);
    for (k, p) in pts.iter().enumerate() {
        if kept.last().is_none_or(|q| q.0 != *p) {
            kept.push((*p, levels[k.min(3)]));
        }
    }
    if kept.len() > 1 && kept[0].0 == kept[kept.len() - 1].0 {
        kept.pop();
    }
    if kept.len() < 3 {
        return;
    }
    let pts: Vec<[f32; 3]> = kept.iter().map(|q| q.0).collect();
    let levels = [0, 1, 2, 3].map(|k| kept.get(k).map_or(OPEN, |q| q.1));
    let pts = pts.as_slice();
    // A tilted top bent along its diagonal (corners held under a strip beside ground that
    // is not) is drawn as its two triangles, each facing its own way, so no half of it
    // faces down against a shared normal.
    if normal.is_none() && pts.len() == 4 {
        let flip = u32::from(levels[0]) + u32::from(levels[2])
            < u32::from(levels[1]) + u32::from(levels[3]);
        let halves: [[usize; 3]; 2] = if flip {
            [[0, 1, 3], [1, 2, 3]]
        } else {
            [[0, 1, 2], [0, 2, 3]]
        };
        let unit = |tri: [usize; 3]| {
            let [p, q, r] = tri.map(|k| pts[k]);
            let c = [
                (q[1] - p[1]) * (r[2] - p[2]) - (q[2] - p[2]) * (r[1] - p[1]),
                (q[2] - p[2]) * (r[0] - p[0]) - (q[0] - p[0]) * (r[2] - p[2]),
                (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]),
            ];
            let len = (c[0] * c[0] + c[1] * c[1] + c[2] * c[2]).sqrt().max(1e-12);
            let sign = if c[1] < 0.0 { -1.0 } else { 1.0 } / len;
            c.map(|x| x * sign)
        };
        let (n0, n1) = (unit(halves[0]), unit(halves[1]));
        if n0[0] * n1[0] + n0[1] * n1[1] + n0[2] * n1[2] < 0.995 {
            for tri in halves {
                let tri_levels = [levels[tri[0]], levels[tri[1]], levels[tri[2]], OPEN];
                push_poly(out, &tri.map(|k| pts[k]), None, colour, tri_levels);
            }
            return;
        }
    }
    // Newell's normal: right for non-planar quads and for quads with a collapsed edge.
    let mut nw = [0.0f32; 3];
    for k in 0..pts.len() {
        let (p, q) = (pts[k], pts[(k + 1) % pts.len()]);
        nw[0] += (p[1] - q[1]) * (p[2] + q[2]);
        nw[1] += (p[2] - q[2]) * (p[0] + q[0]);
        nw[2] += (p[0] - q[0]) * (p[1] + q[1]);
    }
    let len = (nw[0] * nw[0] + nw[1] * nw[1] + nw[2] * nw[2]).sqrt();
    if len < 1e-7 {
        return;
    }
    let face = normal.unwrap_or_else(|| {
        let s = if nw[1] > 0.0 { 1.0 } else { -1.0 } / len;
        nw.map(|x| x * s)
    });
    let dot = nw[0] * face[0] + nw[1] * face[1] + nw[2] * face[2];
    let base = out.positions.len() as u32;
    for (k, p) in pts.iter().enumerate() {
        out.positions.push(*p);
        out.normals.push(face);
        out.colours.push(colour);
        out.shade.push(levels[k.min(3)]);
    }
    // Shading is blended across each triangle; splitting along the diagonal whose ends are
    // the brighter pair keeps a dark corner from drawing a crease across the face.
    let flip =
        u32::from(levels[0]) + u32::from(levels[2]) < u32::from(levels[1]) + u32::from(levels[3]);
    let fan: &[u32] = match (pts.len(), flip) {
        (4, false) => &[0, 1, 2, 0, 2, 3],
        (4, true) => &[0, 1, 3, 1, 2, 3],
        _ => &[0, 1, 2],
    };
    // Godot draws clockwise triangles as front faces: the winding's own normal (Newell's,
    // counter-clockwise positive) has to point away from the face's.
    if dot < 0.0 {
        out.indices.extend(fan.iter().map(|k| base + k));
    } else {
        out.indices.extend(
            fan.chunks(3)
                .flat_map(|tri| [tri[0], tri[2], tri[1]])
                .map(|k| base + k),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tile<'a>(heights: &'a [f32], cn: usize, colours: &'a [Colour]) -> Tile<'a> {
        Tile {
            heights,
            cn,
            spacing: 4.0,
            colours,
            cc: 2,
            n: 16,
            voxel: 0.5,
            steep_slope: 1.0,
            steep: 0x777777,
            side: 0x553311,
            skirt: 1.0,
            seed: 1,
            corners: false,
            tilt_grade: 0.0,
            band: 4.0,
            pad_band: 6.0,
            band_grade: 1.3,
            ways: &[],
            look: Look::default(),
            dug: &[],
        }
    }

    fn cross(u: [f32; 3], w: [f32; 3]) -> [f32; 3] {
        [
            u[1] * w[2] - u[2] * w[1],
            u[2] * w[0] - u[0] * w[2],
            u[0] * w[1] - u[1] * w[0],
        ]
    }

    fn sub(p: [f32; 3], q: [f32; 3]) -> [f32; 3] {
        [p[0] - q[0], p[1] - q[1], p[2] - q[2]]
    }

    fn dot(p: [f32; 3], q: [f32; 3]) -> f32 {
        p[0] * q[0] + p[1] * q[1] + p[2] * q[2]
    }

    fn triangles(m: &Mesh) -> impl Iterator<Item = ([[f32; 3]; 3], [f32; 3])> + '_ {
        m.indices.chunks(3).map(|tri| {
            let p = [tri[0], tri[1], tri[2]].map(|i| m.positions[i as usize]);
            (p, m.normals[tri[0] as usize])
        })
    }

    /// Whether (u, v) lies in the triangle (u0, v0), (u1, v1), (u2, v2), edges included.
    fn inside(p: [f32; 2], t: [[f32; 2]; 3]) -> bool {
        let side = |a: [f32; 2], b: [f32; 2]| {
            (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
        };
        let s = [side(t[0], t[1]), side(t[1], t[2]), side(t[2], t[0])];
        let eps = 1e-5;
        s.iter().all(|&x| x >= -eps) || s.iter().all(|&x| x <= eps)
    }

    /// The highest top face over (x, z), from the mesh alone.
    fn top_at(m: &Mesh, x: f32, z: f32) -> Option<f32> {
        let mut best: Option<f32> = None;
        for (p, n) in triangles(m) {
            if n[1] < 1e-3 || !inside([x, z], p.map(|q| [q[0], q[2]])) {
                continue;
            }
            // The plane through the triangle, solved for y.
            let nn = cross(sub(p[1], p[0]), sub(p[2], p[0]));
            if nn[1].abs() < 1e-9 {
                continue;
            }
            let y = p[0][1] - (nn[0] * (x - p[0][0]) + nn[2] * (z - p[0][2])) / nn[1];
            best = Some(best.map_or(y, |b: f32| b.max(y)));
        }
        best
    }

    fn assert_front_faces_match_normals(m: &Mesh) {
        for (p, n) in triangles(m) {
            let c = cross(sub(p[1], p[0]), sub(p[2], p[0]));
            assert!(
                dot(c, n) <= 1e-6,
                "triangle {p:?} winds the wrong way for its normal {n:?}"
            );
        }
    }

    /// Every shared column edge inside the tile is closed: wherever the tops either side
    /// stand at different heights, a wall covers the gap between them.
    fn assert_closed(t: &Tile, m: &Mesh) {
        let (n, v) = (t.n, t.voxel);
        let walls: Vec<_> = triangles(m).filter(|(_, nn)| nn[1].abs() < 1e-6).collect();
        for b in 0..n {
            for a in 0..n {
                for (along_x, ok) in [(true, a + 1 < n), (false, b + 1 < n)] {
                    if !ok {
                        continue;
                    }
                    for k in [0.25f32, 0.5, 0.75] {
                        // A point on the edge, and a step either side of it.
                        let (x, z) = if along_x {
                            ((a + 1) as f32 * v, (b as f32 + k) * v)
                        } else {
                            ((a as f32 + k) * v, (b + 1) as f32 * v)
                        };
                        let (dx, dz) = if along_x { (0.001, 0.0) } else { (0.0, 0.001) };
                        let lo = top_at(m, x - dx, z - dz).unwrap();
                        let hi = top_at(m, x + dx, z + dz).unwrap();
                        if (lo - hi).abs() < 0.02 {
                            continue;
                        }
                        let y = (lo + hi) / 2.0;
                        let covered = walls.iter().any(|(p, _)| {
                            let flat =
                                |q: [f32; 3]| if along_x { [q[2], q[1]] } else { [q[0], q[1]] };
                            let on_plane = p.iter().all(|q| {
                                if along_x {
                                    (q[0] - x).abs() < 1e-4
                                } else {
                                    (q[2] - z).abs() < 1e-4
                                }
                            });
                            on_plane && inside(flat([x, y, z]), p.map(flat))
                        });
                        assert!(
                            covered,
                            "gap between columns at ({x}, {y}, {z}): {lo} against {hi}"
                        );
                    }
                }
            }
        }
    }

    /// Every wall faces the lower of the two columns it stands between.
    fn assert_walls_face_down_the_step(m: &Mesh) {
        for (p, nn) in triangles(m) {
            if nn[1].abs() > 1e-6 {
                continue;
            }
            let c = [0, 1, 2].map(|k| (p[0][k] + p[1][k] + p[2][k]) / 3.0);
            let (Some(front), Some(behind)) = (
                top_at(m, c[0] + nn[0] * 0.01, c[2] + nn[2] * 0.01),
                top_at(m, c[0] - nn[0] * 0.01, c[2] - nn[2] * 0.01),
            ) else {
                continue;
            };
            assert!(
                front <= c[1] + 5e-3 && behind >= c[1] - 5e-3,
                "a wall at {c:?} faces up its step ({front} in front, {behind} behind)"
            );
        }
    }

    #[test]
    fn tops_darken_at_the_foot_of_a_step_only_when_asked() {
        // Rising along x, so every column has a higher neighbour on its +x side.
        let heights = [0.0, 6.0, 0.0, 6.0];
        let colours = [0x00FF00; 4];
        let mut t = tile(&heights, 2, &colours);
        let plain = mesh(&t);
        assert!(plain.shade.iter().all(|&l| l == crate::OPEN));
        t.corners = true;
        let shaded = mesh(&t);
        let tops: Vec<u8> = (0..shaded.positions.len())
            .filter(|&i| shaded.normals[i] == [0.0, 1.0, 0.0])
            .map(|i| shaded.shade[i])
            .collect();
        assert!(tops.iter().any(|&l| l < crate::OPEN));
        // Sides stay open.
        assert!(
            (0..shaded.positions.len())
                .filter(|&i| shaded.normals[i][1] == 0.0)
                .all(|i| shaded.shade[i] == crate::OPEN)
        );
    }

    #[test]
    fn flat_shaded_ground_stays_open_and_merged() {
        let heights = [2.0; 9];
        let colours = [0x00FF00; 4];
        let mut t = tile(&heights, 3, &colours);
        t.corners = true;
        let m = mesh(&t);
        assert_eq!(m.quad_count(), 1 + 4 * 16);
        assert!(m.shade.iter().all(|&l| l == crate::OPEN));
    }

    #[test]
    fn flat_ground_is_one_top_and_the_skirt() {
        let heights = [2.0; 9];
        let colours = [0x00FF00; 4];
        let m = mesh(&tile(&heights, 3, &colours));
        // One merged top, plus one skirt wall per column along each of the 4 edges.
        assert_eq!(m.quad_count(), 1 + 4 * 16);
        assert!(m.positions.iter().any(|p| (p[1] - 2.0).abs() < 1e-5));
    }

    #[test]
    fn a_step_gets_a_wall_between_the_levels() {
        // Left half at 0, right half at 2 (coarse grid 3x3, 4 m apart, tile 8 m).
        let heights = [0.0, 0.0, 2.0, 0.0, 0.0, 2.0, 0.0, 0.0, 2.0];
        let colours = [0x00FF00; 4];
        let t = tile(&heights, 3, &colours);
        let m = mesh(&t);
        let walls_facing_left = m.normals.iter().filter(|n| n[0] < -0.5).count() / 4;
        assert!(walls_facing_left >= 16, "{walls_facing_left}");
        assert_closed(&t, &m);
        assert_walls_face_down_the_step(&m);
    }

    #[test]
    fn steep_ground_shows_the_steep_colour() {
        let heights = [0.0, 0.0, 30.0, 0.0, 0.0, 30.0, 0.0, 0.0, 30.0];
        let colours = [0x00FF00; 4];
        let m = mesh(&tile(&heights, 3, &colours));
        assert!(m.colours.contains(&0x777777));
    }

    #[test]
    fn heights_step_in_whole_voxels() {
        let heights = [1.13; 9];
        let colours = [0x00FF00; 4];
        let m = mesh(&tile(&heights, 3, &colours));
        let top = m.positions.iter().map(|p| p[1]).fold(f32::MIN, f32::max);
        assert!((top - 1.0).abs() < 1e-5, "{top}");
    }

    #[test]
    fn a_gentle_slope_tilts_its_tops_and_closes_every_edge() {
        // Rising 1 m over 8 m along x and a little along z: grades about 0.13.
        let heights = [0.0, 0.5, 1.0, 0.1, 0.6, 1.1, 0.25, 0.75, 1.25];
        let colours = [0x00FF00; 4];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        t.corners = true;
        let m = mesh(&t);
        assert_front_faces_match_normals(&m);
        assert_closed(&t, &m);
        // Tilted tops face up and a little downhill (-x); no wall inside the tile.
        assert!(m.normals.iter().any(|n| n[1] > 0.5 && n[0] < -0.05));
        assert!(
            triangles(&m)
                .filter(|(_, n)| n[1].abs() < 1e-6)
                .all(|(p, _)| p
                    .iter()
                    .all(|q| q[0] < 1e-4 || q[0] > 8.0 - 1e-4 || q[2] < 1e-4 || q[2] > 8.0 - 1e-4))
        );
    }

    #[test]
    fn a_steep_slope_keeps_its_steps() {
        let heights = [0.0, 6.0, 12.0, 0.0, 6.0, 12.0, 0.0, 6.0, 12.0];
        let colours = [0x00FF00; 4];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        let m = mesh(&t);
        assert_front_faces_match_normals(&m);
        assert!(m.normals.iter().all(|n| n[1] == 0.0 || n[1] == 1.0));
        assert_closed(&t, &m);
        assert_walls_face_down_the_step(&m);
    }

    #[test]
    fn where_gentle_meets_steep_the_walls_close_and_face_down() {
        // Gentle on the left half, a steep rise on the right.
        let heights = [0.0, 0.6, 5.0, 0.2, 0.8, 5.5, 0.0, 0.7, 6.0];
        let colours = [0x00FF00; 4];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        t.corners = true;
        let m = mesh(&t);
        assert!(m.normals.iter().any(|n| n[1] > 0.5 && n[1] < 0.9999));
        assert!(m.normals.contains(&[0.0, 1.0, 0.0]));
        assert_front_faces_match_normals(&m);
        assert_closed(&t, &m);
        assert_walls_face_down_the_step(&m);
    }

    #[test]
    fn ground_under_a_strip_stays_below_it_and_beside_it_tilts_to_meet_it() {
        // A steep-ish bank (grade 0.5) with a level road strip across it along z at x = 4.
        let heights = [0.0, 2.0, 4.0, 0.0, 2.0, 4.0, 0.0, 2.0, 4.0];
        let colours = [0x00FF00; 4];
        let road = [4.0, -1.0, 2.0, 4.0, 9.0, 2.0, 1.0, 0.0];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        t.ways = &road;
        let m = mesh(&t);
        assert_front_faces_match_normals(&m);
        assert_closed(&t, &m);
        assert_walls_face_down_the_step(&m);
        for z in [0.3, 4.1, 7.7] {
            for x in [3.2, 4.0, 4.8] {
                let top = top_at(&m, x, z).unwrap();
                assert!(top <= 2.0 - 0.02 + 1e-4, "{top} at ({x}, {z})");
            }
            // Beside the edge the tops tilt (grade 0.5 is under the band's 1.0).
            let beside = (0..m.positions.len()).any(|i| {
                let p = m.positions[i];
                (p[2] - z).abs() < 0.6
                    && (p[0] - 5.5).abs() < 0.6
                    && m.normals[i][1] > 0.5
                    && m.normals[i][1] < 0.9999
            });
            assert!(beside, "no tilted top beside the strip at z {z}");
        }
    }

    #[test]
    fn a_band_steeper_than_its_cap_keeps_its_steps() {
        let heights = [0.0, 2.0, 4.0, 0.0, 2.0, 4.0, 0.0, 2.0, 4.0];
        let colours = [0x00FF00; 4];
        let road = [4.0, -1.0, 2.0, 4.0, 9.0, 2.0, 1.0, 1.0];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        t.band_grade = 0.4;
        t.ways = &road;
        let m = mesh(&t);
        // Only the columns under the strip tilt.
        for i in 0..m.positions.len() {
            let n = m.normals[i];
            if n[1] > 0.5 && n[1] < 0.9999 {
                assert!(
                    (m.positions[i][0] - 4.0).abs() <= 1.0 + 0.5 + 1e-4,
                    "{:?}",
                    m.positions[i]
                );
            }
        }
        assert_closed(&t, &m);
        assert_walls_face_down_the_step(&m);
    }

    #[test]
    fn rolling_ground_near_the_tilt_limit_stays_closed_beside_a_track() {
        // Grades wandering either side of the limit, a track across, every seed.
        for seed in 0..40u32 {
            let heights: Vec<f32> = (0..25)
                .map(|i| {
                    let (x, z) = ((i % 5) as f32, (i / 5) as f32);
                    x * 1.6 + z * 0.4 + hash(i, 3, 5, seed) * 1.5
                })
                .collect();
            let colours = [0x00FF00; 4];
            let track = [-1.0, 3.0, 4.0, 17.0, 5.0, 6.0, 1.75, 1.0];
            let mut t = tile(&heights, 5, &colours);
            t.n = 32;
            t.tilt_grade = 0.34;
            t.band = 4.0;
            t.band_grade = 1.3;
            t.corners = true;
            t.ways = &track;
            let m = mesh(&t);
            assert_front_faces_match_normals(&m);
            assert_closed(&t, &m);
            assert_walls_face_down_the_step(&m);
        }
    }

    #[test]
    fn a_lane_is_painted_within_its_width_and_verge() {
        let heights = [0.0; 9];
        let colours = [0x00FF00; 4];
        let lane = [4.0, -1.0, 0.0, 4.0, 9.0, 0.0, 1.5, 2.0];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        t.ways = &lane;
        let m = mesh(&t);
        let painted: Vec<f32> = (0..m.positions.len())
            .filter(|&i| m.normals[i][1] > 0.5 && m.colours[i] != 0x00FF00)
            .map(|i| m.positions[i][0])
            .collect();
        assert!(!painted.is_empty());
        // Every painted top lies within the lane and one cell of verge (its corners up to a
        // cell further).
        assert!(
            painted
                .iter()
                .all(|&x| (x - 4.0).abs() <= 1.5 + 0.5 + 0.5 + 1e-4),
            "{painted:?}"
        );
        assert!(m.colours.contains(&ways::mix(
            Look::default().lane_soil,
            0x00FF00,
            Look::default().lane_mix
        )));
        assert!(m.colours.contains(&0x00FF00));
    }

    #[test]
    fn a_crater_in_a_lane_keeps_the_ground_colour() {
        // A metre-spaced grid with a 2 m deep hole in the middle of the lane.
        let mut heights = [0.0; 81];
        for (i, h) in heights.iter_mut().enumerate() {
            if (3..=5).contains(&(i % 9)) && (3..=5).contains(&(i / 9)) {
                *h = -2.0;
            }
        }
        let dug: Vec<u8> = heights.iter().map(|&h| u8::from(h < -1.0)).collect();
        let colours = [0x00FF00; 4];
        let lane = [4.0, -1.0, 0.0, 4.0, 9.0, 0.0, 1.5, 2.0];
        let mut t = tile(&heights, 9, &colours);
        t.spacing = 1.0;
        t.ways = &lane;
        t.dug = &dug;
        let m = mesh(&t);
        let bottom = (0..m.positions.len())
            .find(|&i| m.normals[i][1] > 0.5 && (m.positions[i][1] + 2.0).abs() < 0.3);
        assert!(bottom.is_some_and(|i| m.colours[i] == 0x00FF00));
    }

    #[test]
    fn level_ground_that_tilts_still_merges_into_one_top() {
        let heights = [2.0; 9];
        let colours = [0x00FF00; 4];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        t.corners = true;
        let (m, tilted) = mesh_marked(&t);
        assert_eq!(m.quad_count(), 1 + 4 * 16);
        assert!(tilted.is_empty());
    }

    #[test]
    fn sloping_tilted_tops_are_marked_and_only_they() {
        // Rising 1 cm over 8 m: tilted, but nearly level.
        let heights = [0.0, 0.005, 0.01, 0.0, 0.005, 0.01, 0.0, 0.005, 0.01];
        let colours = [0x00FF00; 4];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        let (m, tilted) = mesh_marked(&t);
        assert!(!tilted.is_empty());
        for i in 0..m.positions.len() {
            let top = m.normals[i][1] > 0.3;
            assert_eq!(tilted.contains(&i), top, "vertex {i} {:?}", m.normals[i]);
        }
    }

    /// The heights the mesh shows along x = `x`, every `step` metres in z (the corners both
    /// details share).
    fn profile(m: &Mesh, x: f32, inward: f32, step: f32, to: f32) -> Vec<f32> {
        let mut out = Vec::new();
        let mut z = step;
        while z < to {
            out.push(top_at(m, x + inward, z).unwrap());
            z += step;
        }
        out
    }

    #[test]
    fn neighbouring_tiles_and_details_agree_on_the_ground_under_a_strip() {
        // Two 8 m tiles side by side along x on a gentle slope, a road crossing the seam,
        // one at 0.5 m voxels and the other at 0.25 m.
        let left = [0.0, 0.4, 0.8, 0.0, 0.4, 0.8, 0.0, 0.4, 0.8];
        let right = [0.8, 1.2, 1.6, 0.8, 1.2, 1.6, 0.8, 1.2, 1.6];
        let colours = [0x00FF00; 4];
        let road_left = [0.0, 4.0, 0.3, 16.0, 4.0, 1.1, 1.5, 0.0];
        let road_right = [-8.0, 4.0, 0.3, 8.0, 4.0, 1.1, 1.5, 0.0];
        let mut a = tile(&left, 3, &colours);
        a.tilt_grade = 0.34;
        a.ways = &road_left;
        let mut b = tile(&right, 3, &colours);
        b.tilt_grade = 0.34;
        b.ways = &road_right;
        b.n = 32;
        b.voxel = 0.25;
        let (ma, mb) = (mesh(&a), mesh(&b));
        // Along the seam, at the corners both share.
        let pa = profile(&ma, 8.0, -0.01, 0.5, 8.0);
        let pb = profile(&mb, 0.0, 0.01, 0.5, 8.0);
        for (k, (ha, hb)) in pa.iter().zip(&pb).enumerate() {
            assert!((ha - hb).abs() < 0.03, "{k}: {ha} against {hb}");
        }
    }

    #[test]
    fn crossing_strips_keep_the_ground_under_both() {
        let heights = [1.0; 9];
        let colours = [0x00FF00; 4];
        let ways = [
            0.0, 4.0, 1.0, 8.0, 4.0, 1.0, 1.5, 0.0, //
            4.0, 0.0, 0.9, 4.0, 8.0, 0.9, 1.5, 1.0,
        ];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        t.ways = &ways;
        let m = mesh(&t);
        assert_closed(&t, &m);
        // Where they cross, under the lower.
        assert!(top_at(&m, 4.0, 4.0).unwrap() <= 0.9 - 0.02 + 1e-4);
    }

    #[test]
    fn a_step_above_tilted_ground_leaves_no_crevice() {
        // Gentle on the left, steeper (stepped) on the right, rising away.
        let heights = [0.0, 0.6, 3.0, 0.0, 0.6, 3.0, 0.0, 0.6, 3.0];
        let colours = [0x00FF00; 4];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        let m = mesh(&t);
        // Just past the last tilted column the step is no lower than the slope's edge.
        let mut z = 0.25;
        while z < 8.0 {
            let mut x = 0.25;
            while x < 7.75 {
                let here = top_at(&m, x, z).unwrap();
                let next = top_at(&m, x + 0.5, z).unwrap();
                assert!(next >= here - 0.1, "dip at ({x}, {z}): {here} then {next}");
                x += 0.5;
            }
            z += 0.5;
        }
    }

    #[test]
    fn a_gentle_slope_merges_one_top_per_sample_cell() {
        let heights = [0.0, 0.5, 1.0, 0.1, 0.6, 1.1, 0.25, 0.75, 1.25];
        let colours = [0x00FF00; 4];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        let m = mesh(&t);
        // Four cells of 8 x 8 columns, each one top (split in two where it twists), and the
        // skirts.
        let tops = m.indices.len() / 3 - 64 * 2;
        assert!(tops <= 4 * 2 * 2, "{tops} top triangles");
        assert_closed(&t, &m);
    }

    #[test]
    fn the_bank_round_a_pad_tilts_into_it() {
        // A pad over the left quarter, its bank rising at 0.6 to the right.
        let heights = [0.0, 1.2, 3.6, 0.0, 1.2, 3.6, 0.0, 1.2, 3.6];
        let colours = [0x00FF00; 4];
        let pad = [-4.0, 4.0, 0.0, 2.0, 4.0, 0.0, 6.0, 4.0];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        let stepped = mesh(&t);
        t.ways = &pad;
        let m = mesh(&t);
        let sloping = |m: &Mesh| {
            (0..m.positions.len())
                .filter(|&i| m.normals[i][1] > 0.3 && m.normals[i][1] < 0.9999)
                .count()
        };
        assert!(sloping(&m) > sloping(&stepped));
        assert_closed(&t, &m);
        assert_walls_face_down_the_step(&m);
    }

    /// No top vertex lies inside another top's edge (a T-junction, drawn as a crack).
    fn assert_no_t_junctions(m: &Mesh) {
        let tops: Vec<[[f32; 3]; 3]> = triangles(m)
            .filter(|(_, n)| n[1] > 1e-3)
            .map(|(p, _)| p)
            .collect();
        let mut points: Vec<[f32; 3]> = tops.iter().flatten().copied().collect();
        points.sort_by(|p, q| p.partial_cmp(q).unwrap());
        points.dedup();
        for tri in &tops {
            for k in 0..3 {
                let (p, q) = (tri[k], tri[(k + 1) % 3]);
                for r in &points {
                    let t = ((r[0] - p[0]) * (q[0] - p[0]) + (r[2] - p[2]) * (q[2] - p[2]))
                        / ((q[0] - p[0]).powi(2) + (q[2] - p[2]).powi(2)).max(1e-9);
                    if t <= 1e-4 || t >= 1.0 - 1e-4 {
                        continue;
                    }
                    let (x, z) = (p[0] + (q[0] - p[0]) * t, p[2] + (q[2] - p[2]) * t);
                    let off = ((r[0] - x).powi(2) + (r[2] - z).powi(2)).sqrt();
                    let y = p[1] + (q[1] - p[1]) * t;
                    assert!(
                        off > 1e-4 || (r[1] - y).abs() > 1e-3,
                        "{r:?} sits inside the edge {p:?} {q:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn tops_meet_corner_to_corner() {
        let heights = [0.0, 0.5, 1.0, 0.1, 0.6, 1.1, 0.25, 0.75, 1.25];
        let colours = [0x00FF00; 4];
        let track = [-1.0, 3.0, 0.4, 9.0, 5.0, 0.8, 1.5, 1.0];
        let mut t = tile(&heights, 3, &colours);
        t.tilt_grade = 0.34;
        t.ways = &track;
        assert_no_t_junctions(&mesh(&t));
        let level = [1.0; 9];
        let mut t = tile(&level, 3, &colours);
        t.tilt_grade = 0.34;
        t.ways = &track;
        assert_no_t_junctions(&mesh(&t));
    }
}
