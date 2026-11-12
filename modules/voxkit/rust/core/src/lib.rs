//! Voxel models made by code: a grid of coloured cells filled with shapes given in metres,
//! and a greedy mesher that turns it into as few quads as possible. Each filled cell also
//! carries a material index (wood, glass, concrete...), which decides how it takes hits; the
//! names and rules behind the indices live in the voxkit materials data file.
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
    /// Material index per cell, 0 ("default") for air and for models that never set one.
    materials: Vec<u8>,
    /// Material that fills write into the cells they fill.
    pub brush: u8,
    /// Materials drawn see-through (glass): the normal mesh treats their cells as air, and a
    /// second "clear" mesh holds only them.
    clear: [bool; 256],
    /// Chunks per axis, and which chunks changed since they were last meshed.
    chunks: [usize; 3],
    dirty: Vec<bool>,
    /// Darken face corners by how many cells crowd them (see `corner_level`).
    pub corners: bool,
}

/// Chunk side in cells: each chunk meshes on its own, so an edit rebuilds only the chunks it
/// touched.
pub const CHUNK: usize = 16;

/// Largest grid side in cells, so a typo in a parameter can't ask for gigabytes.
pub const MAX_SIDE: usize = 1024;
/// Largest cell count (about 64 MB of colours).
pub const MAX_CELLS: usize = 16 * 1024 * 1024;

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Mesh {
    pub positions: Vec<[f32; 3]>,
    pub normals: Vec<[f32; 3]>,
    pub colours: Vec<Colour>,
    /// Per vertex, how open its corner is: 0 (tucked into an inside corner) to 3 (nothing
    /// crowding it). `OPEN` everywhere when corner shading is off.
    pub shade: Vec<u8>,
    pub indices: Vec<u32>,
}

/// Corner level of a vertex nothing crowds.
pub const OPEN: u8 = 3;

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
        let chunks = n.map(|v| v.div_ceil(CHUNK));
        Grid {
            nx: n[0],
            ny: n[1],
            nz: n[2],
            voxel,
            cells: vec![EMPTY; n[0] * n[1] * n[2]],
            materials: vec![0; n[0] * n[1] * n[2]],
            brush: 0,
            clear: [false; 256],
            chunks,
            dirty: vec![true; chunks[0] * chunks[1] * chunks[2]],
            corners: false,
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
            let m = if c == EMPTY { 0 } else { self.brush };
            self.write(x, y, z, c, m);
        }
    }

    /// Draws material `m` see-through (`on`) or not; every chunk is meshed again.
    pub fn set_clear(&mut self, m: u8, on: bool) {
        if self.clear[m as usize] != on {
            self.clear[m as usize] = on;
            self.dirty.iter_mut().for_each(|d| *d = true);
        }
    }

    /// True when some material is drawn see-through.
    pub fn has_clear(&self) -> bool {
        self.clear.iter().any(|&c| c)
    }

    /// Filled and drawn see-through.
    fn clear_at(&self, p: [i64; 3]) -> bool {
        if p.iter().any(|&v| v < 0) {
            return false;
        }
        let (x, y, z) = (p[0] as usize, p[1] as usize, p[2] as usize);
        if x >= self.nx || y >= self.ny || z >= self.nz {
            return false;
        }
        let i = self.index(x, y, z);
        self.cells[i] != EMPTY && self.clear[self.materials[i] as usize]
    }

    /// Material index of cell (x, y, z); 0 for air and outside the grid.
    pub fn material(&self, x: usize, y: usize, z: usize) -> u8 {
        if x >= self.nx || y >= self.ny || z >= self.nz {
            return 0;
        }
        self.materials[self.index(x, y, z)]
    }

    /// Material index of the cell holding `p` (model space, metres); 0 for air and outside.
    pub fn material_at(&self, p: [f32; 3]) -> u8 {
        let o = self.origin();
        let cell = [0, 1, 2].map(|a| ((p[a] - o[a]) / self.voxel).floor());
        if cell.iter().any(|&c| c < 0.0) {
            return 0;
        }
        self.material(cell[0] as usize, cell[1] as usize, cell[2] as usize)
    }

    /// Colour of the cell holding `p` (model space, metres); `EMPTY` for air and outside.
    pub fn colour_at(&self, p: [f32; 3]) -> Colour {
        let o = self.origin();
        let cell = [0, 1, 2].map(|a| ((p[a] - o[a]) / self.voxel).floor() as i64);
        self.get(cell[0], cell[1], cell[2])
    }

    /// The material most filled cells inside the box `min..max` (by cell centre) have,
    /// ignoring 0; 0 when none of them has one.
    pub fn dominant_material(&self, min: [f32; 3], max: [f32; 3]) -> u8 {
        let [(x0, x1), (y0, y1), (z0, z1)] = self.range_centres(min, max);
        let mut counts = [0usize; 256];
        for y in y0..y1 {
            for z in z0..z1 {
                for x in x0..x1 {
                    let i = self.index(x, y, z);
                    if self.cells[i] != EMPTY {
                        counts[self.materials[i] as usize] += 1;
                    }
                }
            }
        }
        (1..256)
            .max_by_key(|&m| (counts[m], std::cmp::Reverse(m)))
            .filter(|&m| counts[m] > 0)
            .map_or(0, |m| m as u8)
    }

    /// Each connected patch (cells sharing a face) of material `m`, as its bounding box in
    /// metres `(min, max)`, in a fixed order (by first cell in storage order), so every
    /// instance numbers them alike.
    pub fn components(&self, m: u8) -> Vec<([f32; 3], [f32; 3])> {
        if m == 0 {
            return Vec::new();
        }
        let n = [self.nx, self.ny, self.nz];
        let mut seen = vec![false; self.cells.len()];
        let mut out = Vec::new();
        let o = self.origin();
        for start in 0..self.cells.len() {
            if seen[start] || self.cells[start] == EMPTY || self.materials[start] != m {
                continue;
            }
            seen[start] = true;
            let mut lo = [usize::MAX; 3];
            let mut hi = [0usize; 3];
            let mut stack = vec![start];
            while let Some(i) = stack.pop() {
                let x = i % self.nx;
                let z = (i / self.nx) % self.nz;
                let y = i / (self.nx * self.nz);
                let p = [x, y, z];
                for a in 0..3 {
                    lo[a] = lo[a].min(p[a]);
                    hi[a] = hi[a].max(p[a]);
                }
                for a in 0..3 {
                    for d in [-1i64, 1] {
                        let v = p[a] as i64 + d;
                        if v < 0 || v as usize >= n[a] {
                            continue;
                        }
                        let mut q = p;
                        q[a] = v as usize;
                        let j = self.index(q[0], q[1], q[2]);
                        if !seen[j] && self.cells[j] != EMPTY && self.materials[j] == m {
                            seen[j] = true;
                            stack.push(j);
                        }
                    }
                }
            }
            let v = self.voxel;
            out.push((
                [0, 1, 2].map(|a| o[a] + lo[a] as f32 * v),
                [0, 1, 2].map(|a| o[a] + (hi[a] + 1) as f32 * v),
            ));
        }
        out
    }

    /// The connected patch (cells sharing a face) of material `m` holding the cell at `p`
    /// (model space), as its bounding box in metres `(min, max)`; `None` when that cell isn't
    /// `m`, or the patch is bigger than `cap` cells (not a single brick but a whole wall).
    pub fn component_at(&self, p: [f32; 3], m: u8, cap: usize) -> Option<([f32; 3], [f32; 3])> {
        let o = self.origin();
        let cell = [0, 1, 2].map(|a| ((p[a] - o[a]) / self.voxel).floor());
        let n = [self.nx, self.ny, self.nz];
        if (0..3).any(|a| cell[a] < 0.0 || cell[a] as usize >= n[a]) {
            return None;
        }
        let start = self.index(cell[0] as usize, cell[1] as usize, cell[2] as usize);
        if m == 0 || self.cells[start] == EMPTY || self.materials[start] != m {
            return None;
        }
        let mut seen = std::collections::HashSet::new();
        seen.insert(start);
        let mut stack = vec![start];
        let mut lo = [usize::MAX; 3];
        let mut hi = [0usize; 3];
        while let Some(i) = stack.pop() {
            let x = i % self.nx;
            let z = (i / self.nx) % self.nz;
            let y = i / (self.nx * self.nz);
            let q = [x, y, z];
            for a in 0..3 {
                lo[a] = lo[a].min(q[a]);
                hi[a] = hi[a].max(q[a]);
            }
            for a in 0..3 {
                for d in [-1i64, 1] {
                    let v = q[a] as i64 + d;
                    if v < 0 || v as usize >= n[a] {
                        continue;
                    }
                    let mut r = q;
                    r[a] = v as usize;
                    let j = self.index(r[0], r[1], r[2]);
                    if self.cells[j] != EMPTY && self.materials[j] == m && seen.insert(j) {
                        if seen.len() > cap {
                            return None;
                        }
                        stack.push(j);
                    }
                }
            }
        }
        let v = self.voxel;
        Some((
            [0, 1, 2].map(|a| o[a] + lo[a] as f32 * v),
            [0, 1, 2].map(|a| o[a] + (hi[a] + 1) as f32 * v),
        ))
    }

    /// How many filled cells of material `m` have their centres inside the box.
    pub fn count_material(&self, min: [f32; 3], max: [f32; 3], m: u8) -> usize {
        let [(x0, x1), (y0, y1), (z0, z1)] = self.range_centres(min, max);
        let mut count = 0;
        for y in y0..y1 {
            for z in z0..z1 {
                for x in x0..x1 {
                    let i = self.index(x, y, z);
                    if self.cells[i] != EMPTY && self.materials[i] == m {
                        count += 1;
                    }
                }
            }
        }
        count
    }

    /// Every write goes through here so the chunks it changes get remeshed. Materials don't
    /// change the mesh, but a cell's material only changes along with a write anyway.
    fn write(&mut self, x: usize, y: usize, z: usize, c: Colour, m: u8) {
        let i = self.index(x, y, z);
        self.materials[i] = m;
        if self.cells[i] == c {
            return;
        }
        self.cells[i] = c;
        let p = [x, y, z];
        let n = [self.nx, self.ny, self.nz];
        let home = p.map(|v| v / CHUNK);
        self.mark(home);
        // A cell on a chunk's face also decides whether the neighbour's facing cell shows a
        // face, so that neighbour is remeshed too.
        for a in 0..3 {
            if p[a].is_multiple_of(CHUNK) && p[a] > 0 {
                let mut c = home;
                c[a] -= 1;
                self.mark(c);
            }
            if p[a] % CHUNK == CHUNK - 1 && p[a] + 1 < n[a] {
                let mut c = home;
                c[a] += 1;
                self.mark(c);
            }
        }
    }

    fn mark(&mut self, c: [usize; 3]) {
        let id = self.chunk_id(c);
        self.dirty[id] = true;
    }

    fn chunk_id(&self, c: [usize; 3]) -> usize {
        (c[1] * self.chunks[2] + c[2]) * self.chunks[0] + c[0]
    }

    /// How many chunks the grid is split into (ids run from 0).
    pub fn chunk_count(&self) -> usize {
        self.dirty.len()
    }

    /// The chunk holding cell (x, y, z).
    pub fn chunk_of(&self, x: usize, y: usize, z: usize) -> usize {
        self.chunk_id([x / CHUNK, y / CHUNK, z / CHUNK])
    }

    /// Chunks changed since they were last meshed, without clearing them.
    pub fn dirty_chunks(&self) -> Vec<usize> {
        (0..self.dirty.len()).filter(|&i| self.dirty[i]).collect()
    }

    /// Cell range (`lo..hi` per axis) of chunk `id`.
    pub fn chunk_cells(&self, id: usize) -> ([usize; 3], [usize; 3]) {
        let [cx, _, cz] = self.chunks;
        let c = [id % cx, id / (cx * cz), (id / cx) % cz];
        let n = [self.nx, self.ny, self.nz];
        let lo = c.map(|v| v * CHUNK);
        let hi = [0, 1, 2].map(|a| (lo[a] + CHUNK).min(n[a]));
        (lo, hi)
    }

    /// The mesh of chunk `id` alone: faces of its own cells, hidden where the neighbouring
    /// chunk's cell is filled.
    pub fn mesh_chunk(&self, id: usize) -> Mesh {
        let (lo, hi) = self.chunk_cells(id);
        self.mesh_region(lo, hi, usize::MAX, false)
    }

    /// The see-through cells of chunk `id` alone (glass): faces only where they meet air.
    pub fn mesh_chunk_clear(&self, id: usize) -> Mesh {
        let (lo, hi) = self.chunk_cells(id);
        self.mesh_region(lo, hi, usize::MAX, true)
    }

    /// Like `remesh_dirty`, with each chunk's see-through mesh beside its normal one.
    pub fn remesh_dirty_layers(&mut self) -> Vec<(usize, Mesh, Mesh)> {
        let ids = self.dirty_chunks();
        let out = ids
            .iter()
            .map(|&id| (id, self.mesh_chunk(id), self.mesh_chunk_clear(id)))
            .collect();
        for id in ids {
            self.dirty[id] = false;
        }
        out
    }

    /// Meshes every changed chunk and marks it clean: `(chunk id, mesh)` per chunk, an empty
    /// mesh where a chunk has nothing left to draw.
    pub fn remesh_dirty(&mut self) -> Vec<(usize, Mesh)> {
        let ids = self.dirty_chunks();
        let out = ids.iter().map(|&id| (id, self.mesh_chunk(id))).collect();
        for id in ids {
            self.dirty[id] = false;
        }
        out
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

    /// A new grid holding a copy of the cells whose centres are inside the box `min..max`
    /// (metres), and where the copy's model origin sits in this model's space, so the copy
    /// drawn there lines up with the original.
    pub fn copy_box(&self, min: [f32; 3], max: [f32; 3]) -> (Grid, [f32; 3]) {
        let [(x0, x1), (y0, y1), (z0, z1)] = self.range_centres(min, max);
        let n = [x1 - x0, y1 - y0, z1 - z0].map(|v| v.max(1));
        let mut out = Grid::new(n.map(|v| v as f32 * self.voxel), self.voxel);
        // Grid::new rounds the size up from metres; make sure it matches exactly.
        out.nx = n[0];
        out.ny = n[1];
        out.nz = n[2];
        out.cells = vec![EMPTY; n[0] * n[1] * n[2]];
        out.materials = vec![0; n[0] * n[1] * n[2]];
        out.brush = self.brush;
        out.clear = self.clear;
        out.chunks = n.map(|v| v.div_ceil(CHUNK));
        out.dirty = vec![true; out.chunks[0] * out.chunks[1] * out.chunks[2]];
        for y in y0..y1 {
            for z in z0..z1 {
                for x in x0..x1 {
                    let from = self.index(x, y, z);
                    let i = out.index(x - x0, y - y0, z - z0);
                    out.cells[i] = self.cells[from];
                    out.materials[i] = self.materials[from];
                }
            }
        }
        let o = self.origin();
        let v = self.voxel;
        let at = [
            o[0] + x0 as f32 * v + n[0] as f32 * v / 2.0,
            o[1] + y0 as f32 * v,
            o[2] + z0 as f32 * v + n[2] as f32 * v / 2.0,
        ];
        (out, at)
    }

    /// Cells whose centres are inside `min..max`, as ranges per axis.
    fn range_centres(&self, min: [f32; 3], max: [f32; 3]) -> [(usize, usize); 3] {
        let o = self.origin();
        let n = [self.nx, self.ny, self.nz];
        let mut out = [(0, 0); 3];
        for a in 0..3 {
            let lo = ((min[a] - o[a]) / self.voxel - 0.5).ceil().max(0.0) as usize;
            let hi = (((max[a] - o[a]) / self.voxel - 0.5).floor() + 1.0).max(0.0) as usize;
            let lo = lo.min(n[a]);
            out[a] = (lo, hi.clamp(lo, n[a]));
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
                Op::Fill(paint) => g.write(x, y, z, paint.at(x, y, z), g.brush),
                Op::Carve => g.write(x, y, z, EMPTY, 0),
                Op::Paint(paint) => {
                    if g.cells[i] != EMPTY {
                        g.write(x, y, z, paint.at(x, y, z), g.materials[i]);
                    }
                }
                Op::Mark(m) => {
                    if g.cells[i] != EMPTY {
                        g.materials[i] = m;
                    }
                }
                Op::CarveMaterial(m) => {
                    if g.cells[i] != EMPTY && g.materials[i] == m {
                        g.write(x, y, z, EMPTY, 0);
                    }
                }
                Op::Recolour(paint, m) => {
                    if g.cells[i] != EMPTY && g.materials[i] == m {
                        g.write(x, y, z, paint.at(x, y, z), m);
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

    fn solid(&self, p: [i64; 3]) -> bool {
        self.get(p[0], p[1], p[2]) != EMPTY
    }

    /// Corner levels of a face whose front cell (the air in front of it) is `front`, with
    /// the face spanning axes `u` and `v`: in the order (-u -v), (+u -v), (+u +v), (-u +v).
    fn corner_levels(&self, front: [i64; 3], u: usize, v: usize) -> [u8; 4] {
        [(-1, -1), (1, -1), (1, 1), (-1, 1)].map(|(su, sv): (i64, i64)| {
            let mut a = front;
            a[u] += su;
            let mut b = front;
            b[v] += sv;
            let mut d = a;
            d[v] += sv;
            corner_level(self.solid(a), self.solid(b), self.solid(d))
        })
    }

    /// Greedy meshing: faces between a filled cell and air, merged into rectangles of the same
    /// colour on each slice.
    pub fn mesh(&self) -> Mesh {
        self.mesh_max_run(usize::MAX)
    }

    /// Like `mesh`, but no merged face is longer than `max_run` cells along z, so the mesh
    /// can be bent afterwards (a road following its curve) without faces cutting corners.
    pub fn mesh_max_run(&self, max_run: usize) -> Mesh {
        self.mesh_region([0, 0, 0], [self.nx, self.ny, self.nz], max_run, false)
    }

    /// Greedy mesh of the cells in `lo..hi` (per axis). Neighbours outside the range still
    /// hide faces, but only cells inside it get faces, so meshes of adjacent ranges meet
    /// without gaps or doubles.
    /// `clear_pass`: mesh only the see-through cells (faces where they meet air); otherwise
    /// everything else, treating see-through cells as air.
    fn mesh_region(
        &self,
        lo: [usize; 3],
        hi: [usize; 3],
        max_run: usize,
        clear_pass: bool,
    ) -> Mesh {
        let max_run = max_run.max(1);
        let mut out = Mesh::default();
        let n = [0, 1, 2].map(|a| hi[a].saturating_sub(lo[a]));
        let o = self.origin();
        let o = [0, 1, 2].map(|a| o[a] + lo[a] as f32 * self.voxel);
        for axis in 0..3 {
            let (u, v) = ((axis + 1) % 3, (axis + 2) % 3);
            // Along z (axis 2) runs are capped; u or v may be z.
            let cap = |a: usize| if a == 2 { max_run } else { usize::MAX };
            for back in [false, true] {
                for slice in 0..n[axis] {
                    let s = Slice {
                        axis,
                        u,
                        v,
                        back,
                        at: lo[axis] + slice,
                    };
                    let mask = self.face_mask(&s, lo, n, clear_pass);
                    for (i, j, w, h, key) in merge_rects(mask, n[u], n[v], cap(u), cap(v)) {
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
                        let (colour, levels) = unpack(key);
                        out.push_quad(corner, du, dv, normal, colour, levels, back);
                    }
                }
            }
        }
        out
    }

    /// Which faces of slice `s` look out into air, as merge keys (`NONE` where there is no
    /// face), over the `n[u]` x `n[v]` cells of the region starting at `lo`.
    fn face_mask(&self, s: &Slice, lo: [usize; 3], n: [usize; 3], clear_pass: bool) -> Vec<u64> {
        let mut mask = vec![NONE; n[s.u] * n[s.v]];
        for j in 0..n[s.v] {
            for i in 0..n[s.u] {
                let mut p = [0i64; 3];
                p[s.axis] = s.at as i64;
                p[s.u] = (lo[s.u] + i) as i64;
                p[s.v] = (lo[s.v] + j) as i64;
                let here = self.get(p[0], p[1], p[2]);
                let mut q = p;
                q[s.axis] += if s.back { -1 } else { 1 };
                if here == EMPTY {
                    continue;
                }
                if clear_pass {
                    // Glass shows only against air.
                    if !self.clear_at(p) || self.solid(q) {
                        continue;
                    }
                } else if self.clear_at(p) || (self.solid(q) && !self.clear_at(q)) {
                    // Glass is air to the rest: the frame's faces behind it are drawn.
                    continue;
                }
                let levels = if self.corners {
                    self.corner_levels(q, s.u, s.v)
                } else {
                    [OPEN; 4]
                };
                mask[j * n[s.u] + i] = pack(here, levels);
            }
        }
        mask
    }
}

/// One slice of faces: cells at depth `at` along `axis`, faces spanning `u` and `v`, looking
/// towards negative `axis` when `back`.
struct Slice {
    axis: usize,
    u: usize,
    v: usize,
    back: bool,
    at: usize,
}

/// A face's merge key: its colour in the low bits and its four corner levels above, so only
/// faces that match in both merge. `NONE` is no face.
const NONE: u64 = u64::MAX;

/// Greedy rectangles of equal keys in a `nu` x `nv` mask, at most `cap_u` by `cap_v` cells:
/// `(i, j, width, height, key)` each.
fn merge_rects(
    mut mask: Vec<u64>,
    nu: usize,
    nv: usize,
    cap_u: usize,
    cap_v: usize,
) -> Vec<(usize, usize, usize, usize, u64)> {
    let mut out = Vec::new();
    for j in 0..nv {
        let mut i = 0;
        while i < nu {
            let c = mask[j * nu + i];
            if c == NONE {
                i += 1;
                continue;
            }
            let mut w = 1;
            while i + w < nu && w < cap_u && mask[j * nu + i + w] == c {
                w += 1;
            }
            let mut h = 1;
            while j + h < nv && h < cap_v && (0..w).all(|k| mask[(j + h) * nu + i + k] == c) {
                h += 1;
            }
            for cell in (0..h).flat_map(|jj| (0..w).map(move |k| (j + jj) * nu + i + k)) {
                mask[cell] = NONE;
            }
            out.push((i, j, w, h, c));
            i += w;
        }
    }
    out
}

impl Mesh {
    /// A quad with corners `corner`, `+du`, `+du+dv`, `+dv`, whose corner levels are
    /// `levels` in that order.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn push_quad(
        &mut self,
        corner: [f32; 3],
        du: [f32; 3],
        dv: [f32; 3],
        normal: [f32; 3],
        c: Colour,
        levels: [u8; 4],
        back: bool,
    ) {
        let base = self.positions.len() as u32;
        for (k, p) in [
            corner,
            add(corner, du),
            add(add(corner, du), dv),
            add(corner, dv),
        ]
        .into_iter()
        .enumerate()
        {
            self.positions.push(p);
            self.normals.push(normal);
            self.colours.push(c);
            self.shade.push(levels[k]);
        }
        // Shading is blended across each triangle; splitting along the diagonal whose ends
        // are the brighter pair keeps a dark corner from drawing a crease across the face.
        let flip = u32::from(levels[0]) + u32::from(levels[2])
            < u32::from(levels[1]) + u32::from(levels[3]);
        // Godot draws clockwise triangles as front faces.
        let tris: [u32; 6] = match (back, flip) {
            (true, false) => [0, 1, 2, 0, 2, 3],
            (false, false) => [0, 2, 1, 0, 3, 2],
            (true, true) => [0, 1, 3, 1, 2, 3],
            (false, true) => [0, 3, 1, 1, 3, 2],
        };
        self.indices.extend(tris.iter().map(|t| base + t));
    }
}

/// How open a face corner is, from the three cells around it in the layer in front of the
/// face: the two beside the corner and the one diagonal to it. Both sides filled closes it
/// (0) whatever the diagonal; otherwise 3 minus how many of the three are filled.
pub fn corner_level(side_a: bool, side_b: bool, diagonal: bool) -> u8 {
    if side_a && side_b {
        return 0;
    }
    OPEN - u8::from(side_a) - u8::from(side_b) - u8::from(diagonal)
}

fn pack(colour: Colour, levels: [u8; 4]) -> u64 {
    let l = levels
        .iter()
        .fold(0u64, |acc, &x| (acc << 2) | u64::from(x & 3));
    (l << 32) | u64::from(colour)
}

fn unpack(key: u64) -> (Colour, [u8; 4]) {
    let l = key >> 32;
    (
        (key & 0xFFFF_FFFF) as Colour,
        [
            ((l >> 6) & 3) as u8,
            ((l >> 4) & 3) as u8,
            ((l >> 2) & 3) as u8,
            (l & 3) as u8,
        ],
    )
}

/// What a fill does to the cells it covers.
#[derive(Debug, Clone, Copy)]
pub enum Op {
    Fill(Paint),
    Carve,
    /// Recolour only cells already filled (road markings on asphalt, moss on stone).
    Paint(Paint),
    /// Set the material of cells already filled, leaving their colour.
    Mark(u8),
    /// Empty the cells of one material, leaving the rest (a pane out of its frame).
    CarveMaterial(u8),
    /// Recolour only the cells of one material (a crack mark on glass, not its frame).
    Recolour(Paint, u8),
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
    fn fills_take_the_brush_material_and_carving_clears_it() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        assert_eq!(g.material(0, 0, 0), 0);
        g.brush = 3;
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 0.5, 0.5], fill(RED));
        g.brush = 5;
        g.fill_box([-0.5, 0.5, -0.5], [0.5, 1.0, 0.5], fill(RED));
        assert_eq!(g.material(2, 1, 2), 3);
        assert_eq!(g.material(2, 8, 2), 5);
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 0.25, 0.5], Op::Carve);
        assert_eq!(g.material(2, 1, 2), 0);
        // Same colour, new material: still a change.
        g.brush = 7;
        g.fill_box([-0.5, 0.5, -0.5], [0.5, 1.0, 0.5], fill(RED));
        assert_eq!(g.material(2, 8, 2), 7);
    }

    #[test]
    fn mark_changes_the_material_of_filled_cells_only() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.brush = 1;
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 0.45, 0.5], fill(RED));
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 1.0, 0.5], Op::Mark(4));
        assert_eq!(g.material(0, 0, 0), 4);
        assert_eq!(g.get(0, 0, 0), RED);
        // Air stays air with no material.
        assert_eq!(g.material(0, 9, 0), 0);
        assert_eq!(g.get(0, 9, 0), EMPTY);
    }

    #[test]
    fn material_at_reads_the_cell_holding_a_point() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.brush = 2;
        g.fill_box([-0.5, 0.0, -0.5], [0.0, 1.0, 0.5], fill(RED));
        assert_eq!(g.material_at([-0.25, 0.5, 0.0]), 2);
        assert_eq!(g.material_at([0.25, 0.5, 0.0]), 0);
        assert_eq!(g.material_at([9.0, 0.5, 0.0]), 0);
        assert_eq!(g.material_at([-0.25, -1.0, 0.0]), 0);
    }

    #[test]
    fn the_dominant_material_is_the_most_common_one_in_the_box() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.brush = 8;
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 1.0, 0.5], fill(RED));
        g.brush = 1;
        g.fill_box([-0.5, 0.0, -0.5], [-0.3, 1.0, 0.5], fill(BLUE));
        assert_eq!(g.dominant_material([-0.5, 0.0, -0.5], [0.5, 1.0, 0.5]), 8);
        assert_eq!(g.dominant_material([-0.5, 0.0, -0.5], [-0.3, 1.0, 0.5]), 1);
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 1.0, 0.5], Op::Carve);
        assert_eq!(g.dominant_material([-0.5, 0.0, -0.5], [0.5, 1.0, 0.5]), 0);
    }

    #[test]
    fn colour_at_reads_the_cell_holding_a_point() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.fill_box([-0.5, 0.0, -0.5], [0.0, 1.0, 0.5], fill(RED));
        assert_eq!(g.colour_at([-0.25, 0.5, 0.0]), RED);
        assert_eq!(g.colour_at([0.25, 0.5, 0.0]), EMPTY);
        assert_eq!(g.colour_at([0.0, -3.0, 0.0]), EMPTY);
    }

    #[test]
    fn components_find_each_connected_patch_of_a_material() {
        let mut g = Grid::new([2.0, 1.0, 1.0], 0.1);
        g.brush = 1;
        g.fill_box([-1.0, 0.0, -0.5], [1.0, 1.0, 0.5], fill(RED));
        g.brush = 4;
        // Two panes apart, and a third material between them.
        g.fill_box([-0.8, 0.3, -0.05], [-0.4, 0.7, 0.05], fill(BLUE));
        g.fill_box([0.4, 0.3, -0.05], [0.8, 0.7, 0.05], fill(BLUE));
        let panes = g.components(4);
        assert_eq!(panes.len(), 2);
        for (min, max) in &panes {
            assert!(max[0] - min[0] > 0.35 && max[0] - min[0] < 0.6);
        }
        assert!(g.components(9).is_empty());
    }

    #[test]
    fn carving_one_material_leaves_the_rest() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.brush = 1;
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 1.0, 0.5], fill(RED));
        g.brush = 4;
        g.fill_box([-0.2, 0.3, -0.1], [0.2, 0.7, 0.1], fill(BLUE));
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 1.0, 0.5], Op::CarveMaterial(4));
        assert_eq!(g.colour_at([0.0, 0.5, 0.0]), EMPTY);
        assert_eq!(g.colour_at([-0.4, 0.5, 0.0]), RED);
    }

    #[test]
    fn recolour_changes_only_one_material() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.brush = 1;
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 1.0, 0.5], fill(RED));
        g.brush = 4;
        g.fill_box([-0.2, 0.3, -0.1], [0.2, 0.7, 0.1], fill(BLUE));
        g.fill_box(
            [-0.5, 0.0, -0.5],
            [0.5, 1.0, 0.5],
            Op::Recolour(Paint::solid(0xFFFFFF), 4),
        );
        assert_eq!(g.colour_at([0.0, 0.5, 0.0]), 0xFFFFFF);
        assert_eq!(g.colour_at([-0.4, 0.5, 0.0]), RED);
        assert_eq!(g.material_at([0.0, 0.5, 0.0]), 4);
    }

    #[test]
    fn component_at_finds_the_one_brick_round_a_point() {
        let mut g = Grid::new([2.0, 1.0, 1.0], 0.1);
        g.brush = 9;
        g.fill_box([-1.0, 0.0, -0.5], [1.0, 1.0, 0.5], fill(RED));
        g.brush = 7;
        // Two bricks with a joint between them.
        g.fill_box([-0.6, 0.2, -0.2], [-0.2, 0.4, 0.2], fill(BLUE));
        g.fill_box([-0.1, 0.2, -0.2], [0.3, 0.4, 0.2], fill(BLUE));
        let (min, max) = g.component_at([-0.4, 0.3, 0.0], 7, 1000).unwrap();
        assert!(min[0] > -0.65 && max[0] < -0.15);
        assert!(g.component_at([0.6, 0.3, 0.0], 7, 1000).is_none());
        // A patch bigger than the cap isn't a brick.
        assert!(g.component_at([0.6, 0.3, 0.0], 9, 50).is_none());
        assert_eq!(
            g.count_material([-1.0, 0.0, -0.5], [1.0, 1.0, 0.5], 7),
            2 * 4 * 2 * 4
        );
    }

    #[test]
    fn see_through_cells_go_in_their_own_mesh() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.brush = 1;
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 1.0, 0.5], fill(RED));
        g.brush = 4;
        g.fill_box([-0.2, 0.3, -0.5], [0.2, 0.7, 0.5], fill(BLUE));
        let before = g.mesh_chunk(0).quad_count();
        g.set_clear(4, true);
        let solid = g.mesh_chunk(0);
        let glass = g.mesh_chunk_clear(0);
        // No glass in the normal mesh, and the frame round the glass now shows faces.
        assert!(solid.colours.iter().all(|&c| c != BLUE));
        assert!(solid.quad_count() > before);
        // Only glass in the clear mesh, and only where it meets air (its two ends).
        assert!(!glass.colours.is_empty() && glass.colours.iter().all(|&c| c == BLUE));
        assert!(glass.normals.iter().all(|n| n[2].abs() == 1.0));
        let layers = g.remesh_dirty_layers();
        assert_eq!(layers.len(), g.chunk_count());
    }

    #[test]
    fn a_copied_box_keeps_its_materials() {
        let mut g = Grid::new([1.0, 1.0, 1.0], 0.1);
        g.brush = 6;
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 1.0, 0.5], fill(BLUE));
        let (copy, _) = g.copy_box([-0.2, 0.2, -0.2], [0.2, 0.6, 0.2]);
        assert_eq!(copy.material(0, 0, 0), 6);
    }

    /// Face area per (colour, normal), in square cells, so float sums compare exactly.
    fn area_by_colour(
        meshes: &[Mesh],
        voxel: f32,
    ) -> std::collections::BTreeMap<(Colour, [i32; 3]), i64> {
        let mut out = std::collections::BTreeMap::new();
        for m in meshes {
            for tri in m.indices.chunks(3) {
                let [a, b, c] = [0, 1, 2].map(|k| m.positions[tri[k] as usize]);
                let ab = sub(b, a);
                let ac = sub(c, a);
                let cross = [
                    ab[1] * ac[2] - ab[2] * ac[1],
                    ab[2] * ac[0] - ab[0] * ac[2],
                    ab[0] * ac[1] - ab[1] * ac[0],
                ];
                let area = dot(cross, cross).sqrt() / 2.0 / (voxel * voxel);
                let n = m.normals[tri[0] as usize].map(|v| v.round() as i32);
                // Two triangles make a quad of whole cells; halves are summed in doubles.
                *out.entry((m.colours[tri[0] as usize], n)).or_insert(0) +=
                    (area * 2.0).round() as i64;
            }
        }
        out
    }

    fn chunk_meshes(g: &Grid) -> Vec<Mesh> {
        (0..g.chunk_count()).map(|id| g.mesh_chunk(id)).collect()
    }

    /// Solid cells' faces that look into air, counted cell by cell (twice, to match the area
    /// sums in half cells).
    fn exposed_faces(g: &Grid) -> i64 {
        let mut count = 0;
        for y in 0..g.ny as i64 {
            for z in 0..g.nz as i64 {
                for x in 0..g.nx as i64 {
                    if g.get(x, y, z) == EMPTY {
                        continue;
                    }
                    for d in [
                        [1, 0, 0],
                        [-1, 0, 0],
                        [0, 1, 0],
                        [0, -1, 0],
                        [0, 0, 1],
                        [0, 0, -1],
                    ] {
                        if g.get(x + d[0], y + d[1], z + d[2]) == EMPTY {
                            count += 2;
                        }
                    }
                }
            }
        }
        count
    }

    /// Models shaped like the kit's: a rock (bumpy blob), a shed (walls, a door and windows
    /// carved out, a roof in another colour), a car (body, cabin, wheels) and a gun at fine
    /// voxels. All are bigger than one chunk.
    fn sample_models() -> Vec<Grid> {
        let jitter = |c: Colour| {
            Op::Fill(Paint {
                colour: c,
                jitter: 0.15,
                seed: 3,
            })
        };
        let mut rock = Grid::new([3.0, 2.0, 2.6], 0.1);
        rock.fill_blob(
            [0.0, 1.0, 0.0],
            [1.4, 0.9, 1.2],
            0.3,
            1.5,
            7,
            jitter(0x777066),
        );
        let mut shed = Grid::new([5.0, 3.6, 4.0], 0.15);
        shed.fill_box([-2.5, 0.0, -2.0], [2.5, 2.8, 2.0], jitter(0x8a6a4a));
        shed.fill_box([-2.3, 0.0, -1.8], [2.3, 2.8, 1.8], Op::Carve);
        shed.fill_box([-0.5, 0.0, -2.1], [0.5, 2.0, -1.7], Op::Carve);
        shed.fill_box([1.0, 1.0, -2.1], [1.8, 1.8, -1.7], Op::Carve);
        shed.fill_box([-2.5, 2.8, -2.0], [2.5, 3.2, 2.0], fill(0x555a60));
        let mut car = Grid::new([2.0, 1.6, 4.2], 0.05);
        car.fill_box([-0.9, 0.3, -2.0], [0.9, 0.9, 2.0], jitter(0x6b2a20));
        car.fill_box([-0.8, 0.9, -0.8], [0.8, 1.4, 0.9], fill(0x99aabb));
        for (x, z) in [(-0.8, -1.3), (0.8, -1.3), (-0.8, 1.3), (0.8, 1.3)] {
            car.fill_ellipsoid([x, 0.35, z], [0.15, 0.35, 0.35], fill(0x202020));
        }
        let mut gun = Grid::new([0.12, 0.3, 1.0], 0.005);
        gun.fill_box([-0.02, 0.15, -0.5], [0.02, 0.2, 0.45], fill(0x303030));
        gun.fill_box([-0.03, 0.05, 0.1], [0.03, 0.17, 0.2], jitter(0x5a4630));
        gun.fill_capsule(
            [0.0, 0.18, -0.48],
            [0.0, 0.18, 0.0],
            0.01,
            0.012,
            fill(0x252525),
        );
        vec![rock, shed, car, gun]
    }

    #[test]
    fn chunk_meshes_cover_the_same_faces_as_the_whole_mesh() {
        for g in sample_models() {
            assert!(g.chunk_count() > 1);
            let whole = area_by_colour(&[g.mesh()], g.voxel);
            let chunked = area_by_colour(&chunk_meshes(&g), g.voxel);
            assert_eq!(chunked, whole);
        }
    }

    #[test]
    fn an_edit_dirties_its_chunk_and_a_neighbour_only_across_a_border() {
        let mut g = Grid::new([4.8, 1.6, 1.6], 0.1);
        g.remesh_dirty();
        assert!(g.dirty_chunks().is_empty());
        // Middle of the first chunk.
        g.set(8, 8, 8, RED);
        assert_eq!(g.dirty_chunks(), vec![g.chunk_of(8, 8, 8)]);
        g.remesh_dirty();
        // Last cell of chunk 0 along x: chunk 1 shares that face.
        g.set(15, 8, 8, RED);
        assert_eq!(
            g.dirty_chunks(),
            vec![g.chunk_of(15, 8, 8), g.chunk_of(16, 8, 8)]
        );
        g.remesh_dirty();
        // First cell of chunk 2 along x.
        g.set(32, 4, 4, BLUE);
        assert_eq!(
            g.dirty_chunks(),
            vec![g.chunk_of(31, 4, 4), g.chunk_of(32, 4, 4)]
        );
        g.remesh_dirty();
        // Writing what is already there changes nothing.
        g.set(32, 4, 4, BLUE);
        assert!(g.dirty_chunks().is_empty());
    }

    #[test]
    fn carving_through_a_chunk_border_leaves_every_face_once() {
        let mut g = Grid::new([4.0, 2.0, 4.0], 0.1);
        g.fill_box([-2.0, 0.0, -2.0], [2.0, 2.0, 2.0], fill(RED));
        g.remesh_dirty();
        // Chunk borders at cells 16 and 32 (metres -0.4 and 1.2 on x and z, 1.6 on y).
        g.fill_ellipsoid([-0.4, 1.6, -0.4], [0.55, 0.45, 0.35], Op::Carve);
        g.fill_box([1.1, 0.2, -2.0], [1.3, 0.5, 2.0], Op::Carve);
        let mut meshes = chunk_meshes(&g);
        let total: i64 = area_by_colour(&meshes, g.voxel).values().sum();
        assert_eq!(total, exposed_faces(&g));
        // Rebuilding only the dirty chunks gives the same faces as rebuilding them all.
        let mut patched = Grid::new([4.0, 2.0, 4.0], 0.1);
        patched.fill_box([-2.0, 0.0, -2.0], [2.0, 2.0, 2.0], fill(RED));
        meshes = chunk_meshes(&patched);
        patched.remesh_dirty();
        patched.fill_ellipsoid([-0.4, 1.6, -0.4], [0.55, 0.45, 0.35], Op::Carve);
        patched.fill_box([1.1, 0.2, -2.0], [1.3, 0.5, 2.0], Op::Carve);
        for (id, m) in patched.remesh_dirty() {
            meshes[id] = m;
        }
        assert_eq!(
            area_by_colour(&meshes, g.voxel),
            area_by_colour(&[g.mesh()], g.voxel)
        );
    }

    #[test]
    fn a_copied_box_holds_the_same_cells_where_they_were() {
        let mut g = Grid::new([2.0, 1.0, 2.0], 0.1);
        g.fill_box([-1.0, 0.0, -1.0], [1.0, 0.5, 1.0], fill(RED));
        g.fill_box([0.2, 0.0, 0.2], [0.4, 0.3, 0.6], fill(BLUE));
        let (copy, at) = g.copy_box([0.0, 0.0, 0.0], [0.6, 0.4, 0.8]);
        assert_eq!((copy.nx, copy.ny, copy.nz), (6, 4, 8));
        for y in 0..copy.ny {
            for z in 0..copy.nz {
                for x in 0..copy.nx {
                    let here = copy.centre(x, y, z);
                    let there = [here[0] + at[0], here[1] + at[1], here[2] + at[2]];
                    let (sx, sy, sz) = (
                        ((there[0] + 1.0) / 0.1).floor() as i64,
                        (there[1] / 0.1).floor() as i64,
                        ((there[2] + 1.0) / 0.1).floor() as i64,
                    );
                    assert_eq!(copy.get(x as i64, y as i64, z as i64), g.get(sx, sy, sz));
                }
            }
        }
        assert_eq!(copy.filled(), 6 * 4 * 8);
    }

    /// Corner levels of the vertices of `m` at `at` on faces facing `normal`.
    fn levels_at(m: &Mesh, at: [f32; 3], normal: [f32; 3]) -> Vec<u8> {
        (0..m.positions.len())
            .filter(|&i| {
                m.normals[i] == normal && (0..3).all(|a| (m.positions[i][a] - at[a]).abs() < 1e-4)
            })
            .map(|i| m.shade[i])
            .collect()
    }

    /// Face area per (colour, normal, corner levels) in square cells, quad by quad.
    fn area_by_shade(
        meshes: &[Mesh],
        voxel: f32,
    ) -> std::collections::BTreeMap<(Colour, [i32; 3], [u8; 4]), i64> {
        let mut out = std::collections::BTreeMap::new();
        for m in meshes {
            for q in (0..m.positions.len()).step_by(4) {
                let du = sub(m.positions[q + 1], m.positions[q]);
                let dv = sub(m.positions[q + 3], m.positions[q]);
                let area =
                    (dot(du, du).sqrt() * dot(dv, dv).sqrt() / (voxel * voxel)).round() as i64;
                let n = m.normals[q].map(|v| v.round() as i32);
                let l = [m.shade[q], m.shade[q + 1], m.shade[q + 2], m.shade[q + 3]];
                *out.entry((m.colours[q], n, l)).or_insert(0) += area;
            }
        }
        out
    }

    #[test]
    fn corner_levels_follow_the_rule() {
        assert_eq!(corner_level(false, false, false), 3);
        assert_eq!(corner_level(false, false, true), 2);
        assert_eq!(corner_level(true, false, false), 2);
        assert_eq!(corner_level(true, false, true), 1);
        assert_eq!(corner_level(true, true, false), 0);
        assert_eq!(corner_level(true, true, true), 0);
    }

    #[test]
    fn a_cube_on_an_open_plane_is_open_at_every_top_corner() {
        let mut g = Grid::new([1.0, 0.5, 1.0], 0.1);
        g.corners = true;
        g.fill_box([-0.5, 0.0, -0.5], [0.5, 0.1, 0.5], fill(BLUE));
        // One cell, x and z from 0 to 0.1, standing on the plane.
        g.fill_box([0.0, 0.1, 0.0], [0.1, 0.2, 0.1], fill(RED));
        let m = g.mesh();
        for at in [
            [0.0, 0.2, 0.0],
            [0.1, 0.2, 0.0],
            [0.1, 0.2, 0.1],
            [0.0, 0.2, 0.1],
        ] {
            assert_eq!(
                levels_at(&m, at, [0.0, 1.0, 0.0]),
                vec![OPEN],
                "top corner {at:?}"
            );
        }
        // The plane darkens where it meets the cube: its corners touch the cube's edges.
        let foot = levels_at(&m, [0.0, 0.1, 0.0], [0.0, 1.0, 0.0]);
        assert!(
            !foot.is_empty() && foot.iter().all(|&l| l < OPEN),
            "{foot:?}"
        );
        // With shading off every corner is open.
        g.corners = false;
        assert!(g.mesh().shade.iter().all(|&l| l == OPEN));
    }

    #[test]
    fn an_inside_corner_closes_and_its_edges_darken() {
        // A floor with two walls meeting at x = 0, z = 0 (an L seen from above).
        let mut g = Grid::new([2.0, 1.0, 2.0], 0.1);
        g.corners = true;
        g.fill_box([-1.0, 0.0, -1.0], [1.0, 0.1, 1.0], fill(BLUE));
        g.fill_box([-0.1, 0.1, -0.1], [0.0, 0.6, 1.0], fill(BLUE));
        g.fill_box([-0.1, 0.1, -0.1], [1.0, 0.6, 0.0], fill(BLUE));
        let m = g.mesh();
        let up = [0.0, 1.0, 0.0];
        // The floor's vertex tucked into the corner between the two walls.
        assert_eq!(levels_at(&m, [0.0, 0.1, 0.0], up), vec![0]);
        // Along the foot of each wall, away from the corner (merged faces only have vertices
        // at their ends, so look at whichever lie on the wall's foot).
        for axis in [0, 2] {
            let along: Vec<u8> = (0..m.positions.len())
                .filter(|&i| {
                    let p = m.positions[i];
                    m.normals[i] == up
                        && (p[1] - 0.1).abs() < 1e-4
                        && p[axis].abs() < 1e-4
                        && p[2 - axis] > 0.05
                        && p[2 - axis] < 0.95
                })
                .map(|i| m.shade[i])
                .collect();
            assert!(
                !along.is_empty() && along.iter().all(|&x| x == 1 || x == 2),
                "axis {axis}: {along:?}"
            );
        }
        // Open floor far from both walls.
        assert!(
            levels_at(&m, [0.8, 0.1, 0.8], up)
                .iter()
                .all(|&x| x == OPEN)
        );
    }

    #[test]
    fn faces_with_different_corner_levels_do_not_merge() {
        let mut g = Grid::new([1.0, 0.4, 0.2], 0.1);
        g.fill_box([-0.5, 0.0, -0.1], [0.5, 0.1, 0.1], fill(RED));
        let plain = g.mesh().quad_count();
        g.fill_box([-0.5, 0.1, -0.1], [-0.4, 0.2, 0.1], fill(RED));
        g.corners = false;
        let without = g.mesh().quad_count();
        g.corners = true;
        let with = g.mesh().quad_count();
        assert_eq!(plain, 6);
        // The strip's top next to the block is darker than the rest, so it is its own quad.
        assert!(with > without, "{with} vs {without}");
    }

    #[test]
    fn shaded_chunk_meshes_match_the_whole_shaded_mesh() {
        for mut g in sample_models() {
            g.corners = true;
            let whole = area_by_shade(&[g.mesh()], g.voxel);
            let chunked = area_by_shade(&chunk_meshes(&g), g.voxel);
            assert_eq!(chunked, whole);
        }
    }

    #[test]
    fn capped_runs_split_long_faces_along_z() {
        let mut g = Grid::new([0.4, 0.4, 4.0], 0.1);
        g.fill_box([-0.2, 0.0, -2.0], [0.2, 0.2, 2.0], fill(RED));
        assert_eq!(g.mesh().quad_count(), 6);
        // 40 cells long, at most 10 per face: top, bottom and both sides split in four.
        assert_eq!(g.mesh_max_run(10).quad_count(), 2 + 4 * 4);
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
