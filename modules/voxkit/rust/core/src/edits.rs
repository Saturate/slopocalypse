//! Destruction as integer edits in a model's own cell grid. The server decides each edit once,
//! in cells; every machine applies the same bytes, so the server and every client end up with
//! identical cells whatever their floating point does, and someone joining late gets the same
//! holes by replaying the list. No floating point inside an edit.
//!
//! Wire form: one tag byte, then little-endian fields; every edit is under 16 bytes. Boxes are
//! cell ranges, `lo` inclusive and `hi` exclusive, clipped to the grid when applied.

use crate::{Colour, EMPTY, Grid};

/// One change to a grid's cells.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Edit {
    /// Empty every cell whose squared distance in cells from `centre` is at most `r2`
    /// (0: just that cell).
    CutSphere { centre: [i16; 3], r2: u16 },
    /// Empty every cell in the box.
    CutBox { lo: [i16; 3], hi: [i16; 3] },
    /// Empty the cells of material `m` in the box, leaving the rest (a pane out of its frame).
    CutMaterial { lo: [i16; 3], hi: [i16; 3], m: u8 },
    /// Recolour the cells of material `m` within the sphere (a crack mark on glass).
    Recolour {
        centre: [i16; 3],
        r2: u16,
        colour: Colour,
        m: u8,
    },
    /// In the box, empty each cell of material `loose` with no face neighbour of material
    /// `holder` (mortar left with no brick on any side).
    CutLoose {
        lo: [i16; 3],
        hi: [i16; 3],
        loose: u8,
        holder: u8,
    },
}

const CUT_SPHERE: u8 = 1;
const CUT_BOX: u8 = 2;
const CUT_MATERIAL: u8 = 3;
const RECOLOUR: u8 = 4;
const CUT_LOOSE: u8 = 5;

/// Why bytes could not be read as edits: the offset where reading stopped.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BadEdits(pub usize);

impl Edit {
    pub fn encode(&self, out: &mut Vec<u8>) {
        match *self {
            Edit::CutSphere { centre, r2 } => {
                out.push(CUT_SPHERE);
                put_cell(out, centre);
                out.extend_from_slice(&r2.to_le_bytes());
            }
            Edit::CutBox { lo, hi } => {
                out.push(CUT_BOX);
                put_cell(out, lo);
                put_cell(out, hi);
            }
            Edit::CutMaterial { lo, hi, m } => {
                out.push(CUT_MATERIAL);
                put_cell(out, lo);
                put_cell(out, hi);
                out.push(m);
            }
            Edit::Recolour {
                centre,
                r2,
                colour,
                m,
            } => {
                out.push(RECOLOUR);
                put_cell(out, centre);
                out.extend_from_slice(&r2.to_le_bytes());
                out.extend_from_slice(&colour.to_le_bytes()[..3]);
                out.push(m);
            }
            Edit::CutLoose {
                lo,
                hi,
                loose,
                holder,
            } => {
                out.push(CUT_LOOSE);
                put_cell(out, lo);
                put_cell(out, hi);
                out.push(loose);
                out.push(holder);
            }
        }
    }

    /// Every edit in `bytes`, in order, or where they stop making sense.
    pub fn decode_all(bytes: &[u8]) -> Result<Vec<Edit>, BadEdits> {
        let mut out = Vec::new();
        let mut r = Reader { bytes, at: 0 };
        while r.at < bytes.len() {
            let start = r.at;
            let bad = BadEdits(start);
            let tag = r.u8().ok_or(bad)?;
            let edit = match tag {
                CUT_SPHERE => Edit::CutSphere {
                    centre: r.cell().ok_or(bad)?,
                    r2: r.u16().ok_or(bad)?,
                },
                CUT_BOX => Edit::CutBox {
                    lo: r.cell().ok_or(bad)?,
                    hi: r.cell().ok_or(bad)?,
                },
                CUT_MATERIAL => Edit::CutMaterial {
                    lo: r.cell().ok_or(bad)?,
                    hi: r.cell().ok_or(bad)?,
                    m: r.u8().ok_or(bad)?,
                },
                RECOLOUR => Edit::Recolour {
                    centre: r.cell().ok_or(bad)?,
                    r2: r.u16().ok_or(bad)?,
                    colour: r.rgb().ok_or(bad)?,
                    m: r.u8().ok_or(bad)?,
                },
                CUT_LOOSE => Edit::CutLoose {
                    lo: r.cell().ok_or(bad)?,
                    hi: r.cell().ok_or(bad)?,
                    loose: r.u8().ok_or(bad)?,
                    holder: r.u8().ok_or(bad)?,
                },
                _ => return Err(bad),
            };
            out.push(edit);
        }
        Ok(out)
    }
}

/// Encodes a list of edits.
pub fn encode_all(edits: &[Edit]) -> Vec<u8> {
    let mut out = Vec::new();
    for e in edits {
        e.encode(&mut out);
    }
    out
}

fn put_cell(out: &mut Vec<u8>, c: [i16; 3]) {
    for v in c {
        out.extend_from_slice(&v.to_le_bytes());
    }
}

struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl Reader<'_> {
    fn take(&mut self, n: usize) -> Option<&[u8]> {
        let s = self.bytes.get(self.at..self.at + n)?;
        self.at += n;
        Some(s)
    }
    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }
    fn u16(&mut self) -> Option<u16> {
        let s = self.take(2)?;
        Some(u16::from_le_bytes([s[0], s[1]]))
    }
    fn i16(&mut self) -> Option<i16> {
        let s = self.take(2)?;
        Some(i16::from_le_bytes([s[0], s[1]]))
    }
    fn cell(&mut self) -> Option<[i16; 3]> {
        Some([self.i16()?, self.i16()?, self.i16()?])
    }
    fn rgb(&mut self) -> Option<Colour> {
        let s = self.take(3)?;
        Some(u32::from_le_bytes([s[0], s[1], s[2], 0]))
    }
}

impl Grid {
    fn size(&self) -> [i64; 3] {
        [self.nx as i64, self.ny as i64, self.nz as i64]
    }

    /// `lo..hi` clipped to the grid, per axis.
    fn clip(&self, lo: [i16; 3], hi: [i16; 3]) -> [(usize, usize); 3] {
        let n = self.size();
        let mut out = [(0, 0); 3];
        for a in 0..3 {
            let l = (lo[a] as i64).clamp(0, n[a]);
            let h = (hi[a] as i64).clamp(l, n[a]);
            out[a] = (l as usize, h as usize);
        }
        out
    }

    fn material_i(&self, p: [i64; 3]) -> u8 {
        let n = self.size();
        if (0..3).any(|a| p[a] < 0 || p[a] >= n[a]) {
            return 0;
        }
        self.material(p[0] as usize, p[1] as usize, p[2] as usize)
    }

    /// Cells within squared distance `r2` of `centre`, clipped to the grid.
    fn sphere(&self, centre: [i16; 3], r2: u16) -> Vec<[usize; 3]> {
        let r = (r2 as f64).sqrt() as i64 + 1;
        let c = centre.map(|v| v as i64);
        let n = self.size();
        let mut out = Vec::new();
        for y in (c[1] - r).max(0)..(c[1] + r + 1).min(n[1]) {
            for z in (c[2] - r).max(0)..(c[2] + r + 1).min(n[2]) {
                for x in (c[0] - r).max(0)..(c[0] + r + 1).min(n[0]) {
                    let d = [x - c[0], y - c[1], z - c[2]];
                    if d[0] * d[0] + d[1] * d[1] + d[2] * d[2] <= r2 as i64 {
                        out.push([x as usize, y as usize, z as usize]);
                    }
                }
            }
        }
        out
    }

    pub fn apply_edit(&mut self, edit: &Edit) {
        match *edit {
            Edit::CutSphere { centre, r2 } => {
                for [x, y, z] in self.sphere(centre, r2) {
                    self.write(x, y, z, EMPTY, 0);
                }
            }
            Edit::CutBox { lo, hi } => {
                let [(x0, x1), (y0, y1), (z0, z1)] = self.clip(lo, hi);
                for y in y0..y1 {
                    for z in z0..z1 {
                        for x in x0..x1 {
                            self.write(x, y, z, EMPTY, 0);
                        }
                    }
                }
            }
            Edit::CutMaterial { lo, hi, m } => {
                let [(x0, x1), (y0, y1), (z0, z1)] = self.clip(lo, hi);
                for y in y0..y1 {
                    for z in z0..z1 {
                        for x in x0..x1 {
                            if self.get(x as i64, y as i64, z as i64) != EMPTY
                                && self.material(x, y, z) == m
                            {
                                self.write(x, y, z, EMPTY, 0);
                            }
                        }
                    }
                }
            }
            Edit::Recolour {
                centre,
                r2,
                colour,
                m,
            } => {
                for [x, y, z] in self.sphere(centre, r2) {
                    if self.get(x as i64, y as i64, z as i64) != EMPTY
                        && self.material(x, y, z) == m
                    {
                        self.write(x, y, z, colour, m);
                    }
                }
            }
            Edit::CutLoose {
                lo,
                hi,
                loose,
                holder,
            } => {
                // Decide every cell before emptying any, so the order cells are visited in
                // can't change the result.
                let [(x0, x1), (y0, y1), (z0, z1)] = self.clip(lo, hi);
                let mut gone = Vec::new();
                for y in y0..y1 {
                    for z in z0..z1 {
                        for x in x0..x1 {
                            if self.get(x as i64, y as i64, z as i64) == EMPTY
                                || self.material(x, y, z) != loose
                            {
                                continue;
                            }
                            let p = [x as i64, y as i64, z as i64];
                            let held = NEIGHBOURS.iter().any(|d| {
                                self.material_i([p[0] + d[0], p[1] + d[1], p[2] + d[2]]) == holder
                            });
                            if !held {
                                gone.push([x, y, z]);
                            }
                        }
                    }
                }
                for [x, y, z] in gone {
                    self.write(x, y, z, EMPTY, 0);
                }
            }
        }
    }

    pub fn apply_edits(&mut self, edits: &[Edit]) {
        for e in edits {
            self.apply_edit(e);
        }
    }

    /// FNV-1a over the size, every cell's colour and every cell's material: equal grids give
    /// equal hashes on every platform.
    pub fn grid_hash(&self) -> u64 {
        let mut h = Fnv::new();
        for v in [self.nx, self.ny, self.nz] {
            h.write(&(v as u32).to_le_bytes());
        }
        for (c, m) in self.cells.iter().zip(&self.materials) {
            h.write(&c.to_le_bytes());
            h.write(&[*m]);
        }
        h.0
    }

    /// The cells as runs of equal (colour, material): count (u32), colour (u32), material
    /// (u8), little-endian, after the grid's size (three u32). Loads back with
    /// `load_snapshot`.
    pub fn snapshot(&self) -> Vec<u8> {
        let mut out = Vec::new();
        for v in [self.nx, self.ny, self.nz] {
            out.extend_from_slice(&(v as u32).to_le_bytes());
        }
        let mut i = 0;
        let n = self.cells.len();
        while i < n {
            let (c, m) = (self.cells[i], self.materials[i]);
            let mut run = 1;
            while i + run < n && self.cells[i + run] == c && self.materials[i + run] == m {
                run += 1;
            }
            out.extend_from_slice(&(run as u32).to_le_bytes());
            out.extend_from_slice(&c.to_le_bytes());
            out.push(m);
            i += run;
        }
        out
    }

    /// Replaces the cells with a `snapshot` of a grid of the same size. Fails, leaving the
    /// grid as it was, if the size differs or the runs don't cover it exactly.
    pub fn load_snapshot(&mut self, bytes: &[u8]) -> Result<(), BadEdits> {
        let mut r = Reader { bytes, at: 0 };
        let size = [0; 3].map(|_| {
            r.take(4)
                .map(|s| u32::from_le_bytes([s[0], s[1], s[2], s[3]]) as usize)
        });
        if size != [Some(self.nx), Some(self.ny), Some(self.nz)] {
            return Err(BadEdits(0));
        }
        let n = self.cells.len();
        let mut cells = Vec::with_capacity(n);
        let mut materials = Vec::with_capacity(n);
        while r.at < bytes.len() {
            let bad = BadEdits(r.at);
            let s = r.take(9).ok_or(bad)?;
            let run = u32::from_le_bytes([s[0], s[1], s[2], s[3]]) as usize;
            let c = u32::from_le_bytes([s[4], s[5], s[6], s[7]]);
            if run == 0 || cells.len() + run > n {
                return Err(bad);
            }
            cells.extend(std::iter::repeat_n(c, run));
            materials.extend(std::iter::repeat_n(s[8], run));
        }
        if cells.len() != n {
            return Err(BadEdits(bytes.len()));
        }
        // Through `write`, so the chunks that changed are meshed again.
        for y in 0..self.ny {
            for z in 0..self.nz {
                for x in 0..self.nx {
                    let i = self.index(x, y, z);
                    self.write(x, y, z, cells[i], materials[i]);
                }
            }
        }
        Ok(())
    }

    /// The cell holding `p` (model space, metres), which may lie outside the grid.
    pub fn cell_of(&self, p: [f32; 3]) -> [i64; 3] {
        let o = self.origin();
        [0, 1, 2].map(|a| ((p[a] - o[a]) / self.voxel).floor() as i64)
    }

    /// The cells whose centres are inside the box `min..max` (metres), as `lo..hi`.
    pub fn cells_in_box(&self, min: [f32; 3], max: [f32; 3]) -> ([i64; 3], [i64; 3]) {
        let r = self.range_centres(min, max);
        (r.map(|v| v.0 as i64), r.map(|v| v.1 as i64))
    }
}

const NEIGHBOURS: [[i64; 3]; 6] = [
    [-1, 0, 0],
    [1, 0, 0],
    [0, -1, 0],
    [0, 1, 0],
    [0, 0, -1],
    [0, 0, 1],
];

struct Fnv(u64);

impl Fnv {
    fn new() -> Fnv {
        Fnv(0xcbf2_9ce4_8422_2325)
    }
    fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.0 ^= *b as u64;
            self.0 = self.0.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Op, Paint};

    fn solid(n: usize) -> Grid {
        let mut g = Grid::new([n as f32 * 0.1; 3], 0.1);
        g.brush = 1;
        let h = n as f32 * 0.05;
        g.fill_box(
            [-h, 0.0, -h],
            [h, h * 2.0, h],
            Op::Fill(Paint::solid(0x808080)),
        );
        g
    }

    fn count(g: &Grid) -> usize {
        g.filled()
    }

    #[test]
    fn every_edit_round_trips_under_sixteen_bytes() {
        let edits = [
            Edit::CutSphere {
                centre: [1, -2, 300],
                r2: 4,
            },
            Edit::CutBox {
                lo: [0, 0, 0],
                hi: [1023, 5, -1],
            },
            Edit::CutMaterial {
                lo: [1, 2, 3],
                hi: [4, 5, 6],
                m: 7,
            },
            Edit::Recolour {
                centre: [9, 8, 7],
                r2: 2,
                colour: 0xABCDEF,
                m: 3,
            },
            Edit::CutLoose {
                lo: [1, 1, 1],
                hi: [2, 2, 2],
                loose: 4,
                holder: 5,
            },
        ];
        for e in edits {
            let mut b = Vec::new();
            e.encode(&mut b);
            assert!(b.len() < 16, "{e:?} is {} bytes", b.len());
            assert_eq!(Edit::decode_all(&b), Ok(vec![e]));
        }
        assert_eq!(Edit::decode_all(&encode_all(&edits)), Ok(edits.to_vec()));
    }

    #[test]
    fn bad_bytes_are_refused_with_where_they_stop() {
        assert_eq!(Edit::decode_all(&[99]), Err(BadEdits(0)));
        let mut b = Vec::new();
        Edit::CutBox {
            lo: [0; 3],
            hi: [1; 3],
        }
        .encode(&mut b);
        let whole = b.len();
        b.extend_from_slice(&[CUT_SPHERE, 1, 0]);
        assert_eq!(Edit::decode_all(&b), Err(BadEdits(whole)));
    }

    #[test]
    fn a_sphere_of_radius_zero_takes_one_cell() {
        let mut g = solid(8);
        let before = count(&g);
        g.apply_edit(&Edit::CutSphere {
            centre: [4, 4, 4],
            r2: 0,
        });
        assert_eq!(count(&g), before - 1);
        assert_eq!(g.get(4, 4, 4), EMPTY);
    }

    #[test]
    fn a_sphere_takes_the_cells_the_integer_formula_says() {
        for r2 in [1u16, 2, 3, 4, 8, 9] {
            let mut g = solid(12);
            g.apply_edit(&Edit::CutSphere {
                centre: [6, 6, 6],
                r2,
            });
            for y in 0..12i64 {
                for z in 0..12i64 {
                    for x in 0..12i64 {
                        let d = (x - 6).pow(2) + (y - 6).pow(2) + (z - 6).pow(2);
                        assert_eq!(
                            g.get(x, y, z) == EMPTY,
                            d <= r2 as i64,
                            "r2 {r2} at {x},{y},{z}"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn boxes_are_clipped_to_the_grid() {
        let mut g = solid(4);
        g.apply_edit(&Edit::CutBox {
            lo: [-5, -5, -5],
            hi: [2, 100, 100],
        });
        assert_eq!(count(&g), 2 * 4 * 4);
        g.apply_edit(&Edit::CutBox {
            lo: [3, 0, 0],
            hi: [1, 4, 4],
        });
        assert_eq!(count(&g), 2 * 4 * 4);
    }

    #[test]
    fn material_cuts_and_recolours_touch_one_material() {
        let mut g = solid(6);
        g.brush = 2;
        g.fill_box(
            [-0.3, 0.0, -0.3],
            [0.0, 0.6, 0.3],
            Op::Fill(Paint::solid(0x0000FF)),
        );
        let blue = count(&g) / 2;
        g.apply_edit(&Edit::Recolour {
            centre: [3, 3, 3],
            r2: 9,
            colour: 0xFFFFFF,
            m: 1,
        });
        assert!(
            g.cells
                .iter()
                .zip(&g.materials)
                .all(|(c, m)| *m != 2 || *c == 0x0000FF)
        );
        g.apply_edit(&Edit::CutMaterial {
            lo: [0; 3],
            hi: [6; 3],
            m: 2,
        });
        assert_eq!(count(&g), 6 * 6 * 6 - blue);
        assert!(g.materials.iter().all(|m| *m != 2));
    }

    #[test]
    fn loose_cells_go_and_held_ones_stay_whatever_the_order() {
        // A row: holder, loose, loose, holder, loose (the middle loose pair touches holders
        // on one side each; the last one only the holder before it).
        let mut g = Grid::new([0.5, 0.1, 0.1], 0.1);
        for (x, m) in [(0, 1u8), (1, 2), (2, 2), (3, 1), (4, 2)] {
            g.brush = m;
            g.set(x, 0, 0, 0x777777);
        }
        g.apply_edit(&Edit::CutBox {
            lo: [0, 0, 0],
            hi: [1, 1, 1],
        });
        g.apply_edit(&Edit::CutLoose {
            lo: [0, 0, 0],
            hi: [5, 1, 1],
            loose: 2,
            holder: 1,
        });
        // Cell 1 lost its holder; 2 and 4 still touch the holder at 3.
        assert_eq!(g.get(1, 0, 0), EMPTY);
        assert_ne!(g.get(2, 0, 0), EMPTY);
        assert_ne!(g.get(4, 0, 0), EMPTY);
    }

    #[test]
    fn the_same_edits_give_the_same_hash() {
        let edits = [
            Edit::CutSphere {
                centre: [3, 5, 2],
                r2: 2,
            },
            Edit::Recolour {
                centre: [6, 6, 6],
                r2: 3,
                colour: 0x112233,
                m: 1,
            },
            Edit::CutBox {
                lo: [0, 0, 0],
                hi: [2, 9, 9],
            },
        ];
        let mut a = solid(10);
        let mut b = solid(10);
        assert_eq!(a.grid_hash(), b.grid_hash());
        a.apply_edits(&edits);
        b.apply_edits(&Edit::decode_all(&encode_all(&edits)).unwrap());
        assert_eq!(a.grid_hash(), b.grid_hash());
        assert_ne!(a.grid_hash(), solid(10).grid_hash());
        // The value itself is fixed: any machine that builds this grid and applies these
        // edits must get it, so platforms can't drift apart unnoticed.
        assert_eq!(a.grid_hash(), EXPECTED_HASH, "got {:#x}", a.grid_hash());
    }

    const EXPECTED_HASH: u64 = 0x3197_5ee6_dc32_8806;

    #[test]
    fn a_snapshot_loads_back_to_the_same_cells() {
        let mut a = solid(10);
        a.apply_edits(&[
            Edit::CutSphere {
                centre: [5, 5, 5],
                r2: 6,
            },
            Edit::Recolour {
                centre: [1, 1, 1],
                r2: 2,
                colour: 0x445566,
                m: 1,
            },
        ]);
        let snap = a.snapshot();
        let mut b = solid(10);
        b.load_snapshot(&snap).unwrap();
        assert_eq!(a.grid_hash(), b.grid_hash());
        let mut wrong = solid(9);
        let before = wrong.grid_hash();
        assert!(wrong.load_snapshot(&snap).is_err());
        assert!(b.load_snapshot(&snap[..snap.len() - 1]).is_err());
        assert_eq!(wrong.grid_hash(), before);
    }

    #[test]
    fn cells_of_points_and_boxes() {
        let g = solid(10);
        assert_eq!(g.cell_of([0.0, 0.0, 0.0]), [5, 0, 5]);
        assert_eq!(g.cell_of([-0.51, 0.05, 0.49]), [-1, 0, 9]);
        assert_eq!(
            g.cells_in_box([-0.1, 0.0, -0.1], [0.1, 0.2, 0.1]),
            ([4, 0, 4], [6, 2, 6])
        );
    }
}
