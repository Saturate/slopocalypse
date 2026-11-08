//! Voxel models made by code: a grid of coloured cells filled with shapes given in metres,
//! and a greedy mesher that turns it into as few quads as possible.
//!
//! Model space: x and z are centred on the grid, y starts at 0, so a model stands on the
//! ground at its origin. Each model picks its own voxel size (a gun wants centimetres, a
//! wall a decimetre or more).

pub mod heightfield;

/// A cell's colour as 0xRRGGBB; `EMPTY` is air.
pub type Colour = u32;
pub const EMPTY: Colour = u32::MAX;

#[derive(Debug, Clone)]
pub struct Grid {
    pub nx: usize,
    pub ny: usize,
    pub nz: usize,
    pub voxel: f32,
    cells: Vec<Colour>,
}

/// Largest grid side in cells, so a typo in a parameter can't ask for gigabytes.
pub const MAX_SIDE: usize = 1024;
/// Largest cell count (about 64 MB of colours).
pub const MAX_CELLS: usize = 16 * 1024 * 1024;

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Mesh {
    pub positions: Vec<[f32; 3]>,
    pub normals: Vec<[f32; 3]>,
    pub colours: Vec<Colour>,
    pub indices: Vec<u32>,
}

impl Mesh {
    pub fn quad_count(&self) -> usize {
        self.indices.len() / 6
    }
}

impl Grid {
    /// A grid covering `size` metres (x, y, z) at `voxel` metres per cell, clamped to the
    /// limits above.
    pub fn new(size: [f32; 3], voxel: f32) -> Grid {
        let voxel = voxel.max(0.002);
        let mut n = size.map(|s| ((s / voxel).ceil().max(1.0) as usize).min(MAX_SIDE));
        while n[0] * n[1] * n[2] > MAX_CELLS {
            n = n.map(|v| (v * 3 / 4).max(1));
        }
        Grid {
            nx: n[0],
            ny: n[1],
            nz: n[2],
            voxel,
            cells: vec![EMPTY; n[0] * n[1] * n[2]],
        }
    }

    fn index(&self, x: usize, y: usize, z: usize) -> usize {
        (y * self.nz + z) * self.nx + x
    }

    pub fn get(&self, x: i64, y: i64, z: i64) -> Colour {
        if x < 0 || y < 0 || z < 0 {
            return EMPTY;
        }
        let (x, y, z) = (x as usize, y as usize, z as usize);
        if x >= self.nx || y >= self.ny || z >= self.nz {
            return EMPTY;
        }
        self.cells[self.index(x, y, z)]
    }

    pub fn set(&mut self, x: usize, y: usize, z: usize, c: Colour) {
        if x < self.nx && y < self.ny && z < self.nz {
            let i = self.index(x, y, z);
            self.cells[i] = c;
        }
    }

    pub fn filled(&self) -> usize {
        self.cells.iter().filter(|&&c| c != EMPTY).count()
    }

    fn origin(&self) -> [f32; 3] {
        [
            -(self.nx as f32) * self.voxel / 2.0,
            0.0,
            -(self.nz as f32) * self.voxel / 2.0,
        ]
    }

    /// Centre of a cell in model space.
    pub fn centre(&self, x: usize, y: usize, z: usize) -> [f32; 3] {
        let o = self.origin();
        [
            o[0] + (x as f32 + 0.5) * self.voxel,
            o[1] + (y as f32 + 0.5) * self.voxel,
            o[2] + (z as f32 + 0.5) * self.voxel,
        ]
    }

    /// Cell range covering a box in metres, clipped to the grid.
    fn range(&self, min: [f32; 3], max: [f32; 3]) -> [(usize, usize); 3] {
        let o = self.origin();
        let n = [self.nx, self.ny, self.nz];
        let mut out = [(0, 0); 3];
        for a in 0..3 {
            let lo = ((min[a] - o[a]) / self.voxel).floor().max(0.0) as usize;
            let hi = (((max[a] - o[a]) / self.voxel).ceil().max(0.0) as usize).min(n[a]);
            out[a] = (lo.min(n[a]), hi);
        }
        out
    }

    /// Runs `f` on every cell whose centre is inside the box `min..max`, with the centre.
    fn each_in(
        &mut self,
        min: [f32; 3],
        max: [f32; 3],
        mut f: impl FnMut(&mut Grid, usize, usize, usize, [f32; 3]),
    ) {
        let [(x0, x1), (y0, y1), (z0, z1)] = self.range(min, max);
        for y in y0..y1 {
            for z in z0..z1 {
                for x in x0..x1 {
                    let c = self.centre(x, y, z);
                    f(self, x, y, z, c);
                }
            }
        }
    }

    /// Applies `op` to cells whose centre `inside` accepts, within the bounding box.
    pub fn apply(
        &mut self,
        min: [f32; 3],
        max: [f32; 3],
        op: Op,
        inside: impl Fn([f32; 3]) -> bool,
    ) {
        self.each_in(min, max, |g, x, y, z, c| {
            if !inside(c) {
                return;
            }
            let i = g.index(x, y, z);
            match op {
                Op::Fill(paint) => g.cells[i] = paint.at(x, y, z),
                Op::Carve => g.cells[i] = EMPTY,
                Op::Paint(paint) => {
                    if g.cells[i] != EMPTY {
                        g.cells[i] = paint.at(x, y, z);
                    }
                }
            }
        });
    }

    pub fn fill_box(&mut self, min: [f32; 3], max: [f32; 3], op: Op) {
        // By cell centre, like every other shape, so float error at the edges can't add a
        // stray layer.
        self.apply(min, max, op, |p| {
            (0..3).all(|a| p[a] >= min[a] && p[a] <= max[a])
        });
    }

    pub fn fill_ellipsoid(&mut self, centre: [f32; 3], radii: [f32; 3], op: Op) {
        let r = radii.map(|v| v.max(1e-4));
        self.apply(sub(centre, r), add(centre, r), op, |p| {
            let d = [
                (p[0] - centre[0]) / r[0],
                (p[1] - centre[1]) / r[1],
                (p[2] - centre[2]) / r[2],
            ];
            dot(d, d) <= 1.0
        });
    }

    /// A tapered capsule from `a` (radius `ra`) to `b` (radius `rb`): trunks and branches.
    pub fn fill_capsule(&mut self, a: [f32; 3], b: [f32; 3], ra: f32, rb: f32, op: Op) {
        let r = ra.max(rb);
        let lo = [a[0].min(b[0]) - r, a[1].min(b[1]) - r, a[2].min(b[2]) - r];
        let hi = [a[0].max(b[0]) + r, a[1].max(b[1]) + r, a[2].max(b[2]) + r];
        let ab = sub(b, a);
        let len2 = dot(ab, ab).max(1e-8);
        self.apply(lo, hi, op, |p| {
            let t = (dot(sub(p, a), ab) / len2).clamp(0.0, 1.0);
            let q = add(a, scale(ab, t));
            let d = sub(p, q);
            let rad = ra + (rb - ra) * t;
            dot(d, d) <= rad * rad
        });
    }

    /// An upright cylinder (posts, barrels).
    pub fn fill_cylinder(&mut self, base: [f32; 3], radius: f32, height: f32, op: Op) {
        let lo = [base[0] - radius, base[1], base[2] - radius];
        let hi = [base[0] + radius, base[1] + height, base[2] + radius];
        self.apply(lo, hi, op, |p| {
            let dx = p[0] - base[0];
            let dz = p[2] - base[2];
            dx * dx + dz * dz <= radius * radius
        });
    }

    /// An ellipsoid whose surface is pushed in and out by noise: rocks, leaf clumps.
    pub fn fill_blob(
        &mut self,
        centre: [f32; 3],
        radii: [f32; 3],
        bumps: f32,
        frequency: f32,
        seed: u32,
        op: Op,
    ) {
        let r = radii.map(|v| v.max(1e-4));
        let grow = 1.0 + bumps.abs();
        let reach = scale(r, grow);
        self.apply(sub(centre, reach), add(centre, reach), op, |p| {
            let d = [
                (p[0] - centre[0]) / r[0],
                (p[1] - centre[1]) / r[1],
                (p[2] - centre[2]) / r[2],
            ];
            let n = noise3(scale(p, frequency), seed) * 2.0 - 1.0;
            dot(d, d).sqrt() <= 1.0 + n * bumps
        });
    }

    /// Greedy meshing: faces between a filled cell and air, merged into rectangles of the same
    /// colour on each slice.
    pub fn mesh(&self) -> Mesh {
        let mut out = Mesh::default();
        let n = [self.nx, self.ny, self.nz];
        let o = self.origin();
        for axis in 0..3 {
            let u = (axis + 1) % 3;
            let v = (axis + 2) % 3;
            for back in [false, true] {
                let mut mask = vec![EMPTY; n[u] * n[v]];
                for slice in 0..n[axis] {
                    // Which faces of this slice look out into air.
                    for j in 0..n[v] {
                        for i in 0..n[u] {
                            let mut p = [0i64; 3];
                            p[axis] = slice as i64;
                            p[u] = i as i64;
                            p[v] = j as i64;
                            let here = self.get(p[0], p[1], p[2]);
                            let mut q = p;
                            q[axis] += if back { -1 } else { 1 };
                            let next = self.get(q[0], q[1], q[2]);
                            mask[j * n[u] + i] = if here != EMPTY && next == EMPTY {
                                here
                            } else {
                                EMPTY
                            };
                        }
                    }
                    // Merge runs into rectangles.
                    for j in 0..n[v] {
                        let mut i = 0;
                        while i < n[u] {
                            let c = mask[j * n[u] + i];
                            if c == EMPTY {
                                i += 1;
                                continue;
                            }
                            let mut w = 1;
                            while i + w < n[u] && mask[j * n[u] + i + w] == c {
                                w += 1;
                            }
                            let mut h = 1;
                            'grow: while j + h < n[v] {
                                for k in 0..w {
                                    if mask[(j + h) * n[u] + i + k] != c {
                                        break 'grow;
                                    }
                                }
                                h += 1;
                            }
                            for jj in 0..h {
                                for k in 0..w {
                                    mask[(j + jj) * n[u] + i + k] = EMPTY;
                                }
                            }
                            let plane = if back { slice } else { slice + 1 } as f32;
                            let mut corner = [0f32; 3];
                            corner[axis] = o[axis] + plane * self.voxel;
                            corner[u] = o[u] + i as f32 * self.voxel;
                            corner[v] = o[v] + j as f32 * self.voxel;
                            let mut du = [0f32; 3];
                            du[u] = w as f32 * self.voxel;
                            let mut dv = [0f32; 3];
                            dv[v] = h as f32 * self.voxel;
                            let mut normal = [0f32; 3];
                            normal[axis] = if back { -1.0 } else { 1.0 };
                            out.push_quad(corner, du, dv, normal, c, back);
                            i += w;
                        }
                    }
                }
            }
        }
        out
    }
}

impl Mesh {
    fn push_quad(
        &mut self,
        corner: [f32; 3],
        du: [f32; 3],
        dv: [f32; 3],
        normal: [f32; 3],
        c: Colour,
        back: bool,
    ) {
        let base = self.positions.len() as u32;
        for p in [
            corner,
            add(corner, du),
            add(add(corner, du), dv),
            add(corner, dv),
        ] {
            self.positions.push(p);
            self.normals.push(normal);
            self.colours.push(c);
        }
        // Godot draws clockwise triangles as front faces.
        let tris: [u32; 6] = if back {
            [0, 1, 2, 0, 2, 3]
        } else {
            [0, 2, 1, 0, 3, 2]
        };
        self.indices.extend(tris.iter().map(|t| base + t));
    }
}

/// What a fill does to the cells it covers.
#[derive(Debug, Clone, Copy)]
pub enum Op {
    Fill(Paint),
    Carve,
    /// Recolour only cells already filled (road markings on asphalt, moss on stone).
    Paint(Paint),
}

/// A colour with per-cell brightness jitter, so big surfaces don't look flat.
#[derive(Debug, Clone, Copy)]
pub struct Paint {
    pub colour: Colour,
    pub jitter: f32,
    pub seed: u32,
}

impl Paint {
    pub fn solid(colour: Colour) -> Paint {
        Paint {
            colour,
            jitter: 0.0,
            seed: 0,
        }
    }

    pub fn at(&self, x: usize, y: usize, z: usize) -> Colour {
        if self.jitter <= 0.0 {
            return self.colour;
        }
        let h = hash(x as u32, y as u32, z as u32, self.seed);
        let k = 1.0 + (h * 2.0 - 1.0) * self.jitter;
        let ch = |shift: u32| (((self.colour >> shift) & 0xFF) as f32 * k).clamp(0.0, 255.0) as u32;
        (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }
}

/// 0..1 from integer coordinates and a seed.
pub fn hash(x: u32, y: u32, z: u32, seed: u32) -> f32 {
    let mut h = x.wrapping_mul(0x8da6_b343)
        ^ y.wrapping_mul(0xd816_3841)
        ^ z.wrapping_mul(0xcb1a_b31f)
        ^ seed.wrapping_mul(0x9e37_79b9);
    h ^= h >> 13;
    h = h.wrapping_mul(0x5bd1_e995);
    h ^= h >> 15;
    (h & 0x00FF_FFFF) as f32 / 16_777_215.0
}

/// Smooth value noise, 0..1.
pub fn noise3(p: [f32; 3], seed: u32) -> f32 {
    let f = p.map(f32::floor);
    let t = [p[0] - f[0], p[1] - f[1], p[2] - f[2]].map(|v| v * v * (3.0 - 2.0 * v));
    let i = f.map(|v| v as i32 as u32);
    let c = |dx: u32, dy: u32, dz: u32| {
        hash(
            i[0].wrapping_add(dx),
            i[1].wrapping_add(dy),
            i[2].wrapping_add(dz),
            seed,
        )
    };
    let lerp = |a: f32, b: f32, t: f32| a + (b - a) * t;
    let x00 = lerp(c(0, 0, 0), c(1, 0, 0), t[0]);
    let x10 = lerp(c(0, 1, 0), c(1, 1, 0), t[0]);
    let x01 = lerp(c(0, 0, 1), c(1, 0, 1), t[0]);
    let x11 = lerp(c(0, 1, 1), c(1, 1, 1), t[0]);
    lerp(lerp(x00, x10, t[1]), lerp(x01, x11, t[1]), t[2])
}

fn add(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}

fn sub(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn scale(a: [f32; 3], k: f32) -> [f32; 3] {
    [a[0] * k, a[1] * k, a[2] * k]
}

fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

#[cfg(test)]
mod tests {
    use super::*;

    const RED: Colour = 0xFF0000;
    const BLUE: Colour = 0x0000FF;

    fn fill(c: Colour) -> Op {
        Op::Fill(Paint::solid(c))
    }

    #[test]
    fn grid_size_follows_the_voxel_size() {
        let g = Grid::new([1.0, 2.0, 0.5], 0.1);
        assert_eq!((g.nx, g.ny, g.nz), (10, 20, 5));
    }

    #[test]
    fn huge_requests_are_clamped() {
        let g = Grid::new([1000.0, 1000.0, 1000.0], 0.01);
        assert!(g.nx * g.ny * g.nz <= MAX_CELLS);
    }

    #[test]
    fn a_solid_box_meshes_to_six_quads() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.fill_box([-0.3, 0.2, -0.3], [0.3, 0.8, 0.3], fill(RED));
        assert_eq!(g.filled(), 6 * 6 * 6);
        assert_eq!(g.mesh().quad_count(), 6);
    }

    #[test]
    fn touching_boxes_share_no_inner_faces() {
        let mut g = Grid::new([2.0, 1.0, 1.0], 0.1);
        g.fill_box([-0.5, 0.0, -0.2], [0.0, 0.4, 0.2], fill(RED));
        g.fill_box([0.0, 0.0, -0.2], [0.5, 0.4, 0.2], fill(RED));
        // Same colour: one merged box.
        assert_eq!(g.mesh().quad_count(), 6);
        g.fill_box([0.0, 0.0, -0.2], [0.5, 0.4, 0.2], fill(BLUE));
        // Two colours: the shared wall stays hidden, the four long sides split in two.
        assert_eq!(g.mesh().quad_count(), 10);
    }

    #[test]
    fn carving_makes_air_and_paint_only_touches_filled_cells() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 0.5, 0.5], fill(RED));
        g.fill_box([-0.1, 0.0, -0.1], [0.1, 0.5, 0.1], Op::Carve);
        assert_eq!(g.filled(), 100 * 5 - 4 * 5);
        g.fill_box(
            [-0.5, 0.5, -0.5],
            [0.5, 1.0, 0.5],
            Op::Paint(Paint::solid(BLUE)),
        );
        assert_eq!(g.get(0, 7, 0), EMPTY);
    }

    #[test]
    fn capsules_and_ellipsoids_fill_roughly_their_volume() {
        let mut g = Grid::new([2.0, 2.0, 2.0], 0.05);
        g.fill_ellipsoid([0.0, 1.0, 0.0], [0.5, 0.5, 0.5], fill(RED));
        let volume = g.filled() as f32 * 0.05f32.powi(3);
        let sphere = 4.0 / 3.0 * std::f32::consts::PI * 0.125;
        assert!(
            (volume - sphere).abs() / sphere < 0.1,
            "{volume} vs {sphere}"
        );
        let mut c = Grid::new([1.0, 2.0, 1.0], 0.05);
        c.fill_capsule([0.0, 0.2, 0.0], [0.0, 1.8, 0.0], 0.2, 0.2, fill(RED));
        assert!(c.filled() > 0);
    }

    #[test]
    fn fills_outside_the_grid_are_clipped() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.fill_box([-5.0, -5.0, -5.0], [5.0, 5.0, 5.0], fill(RED));
        assert_eq!(g.filled(), 1000);
    }

    #[test]
    fn jitter_varies_brightness_but_stays_near_the_colour() {
        let p = Paint {
            colour: 0x808080,
            jitter: 0.2,
            seed: 3,
        };
        let a = p.at(1, 2, 3);
        let b = p.at(4, 5, 6);
        assert_ne!(a, b);
        let r = (a >> 16) & 0xFF;
        assert!((100..=160).contains(&r));
    }

    #[test]
    fn noise_is_smooth_and_seeded() {
        let a = noise3([1.25, 2.5, 3.75], 7);
        let b = noise3([1.26, 2.5, 3.75], 7);
        assert!((a - b).abs() < 0.05);
        assert!((0.0..=1.0).contains(&a));
        assert_ne!(noise3([1.25, 2.5, 3.75], 8), a);
    }

    #[test]
    fn blobs_are_seeded() {
        let mut a = Grid::new([2.0, 2.0, 2.0], 0.05);
        a.fill_blob([0.0, 1.0, 0.0], [0.6, 0.5, 0.6], 0.3, 3.0, 1, fill(RED));
        let mut b = Grid::new([2.0, 2.0, 2.0], 0.05);
        b.fill_blob([0.0, 1.0, 0.0], [0.6, 0.5, 0.6], 0.3, 3.0, 2, fill(RED));
        assert_ne!(a.filled(), b.filled());
    }
}
