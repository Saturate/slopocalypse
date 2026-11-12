//! Voxel ground: a tile of ground heights turned into blocky columns, `voxel` metres square
//! and stepping in `voxel` metres. Heights and colours come in on a coarse grid and are
//! filled in per column here, so the caller only samples a few hundred points per tile.
//! Top faces of equal height and colour merge into rectangles; side faces are drawn only
//! where a neighbour is lower.

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

/// Builds the tile's mesh in tile-local metres (x and z from 0 to `n * voxel`, y as given).
pub fn mesh(t: &Tile) -> Mesh {
    let (tops, colours) = columns(t);
    let levels = if t.corners {
        top_levels(t, &tops)
    } else {
        vec![[OPEN; 4]; t.n * t.n]
    };
    let mut out = Mesh::default();
    push_tops(&mut out, t, &tops, &colours, &levels);
    push_sides(&mut out, t, &tops, &colours);
    out
}

/// Each column's top (in voxels) and colour.
fn columns(t: &Tile) -> (Vec<i32>, Vec<Colour>) {
    let (n, v) = (t.n, t.voxel);
    let mut tops = vec![0i32; n * n];
    let mut colours = vec![0u32; n * n];
    for b in 0..n {
        for a in 0..n {
            let (x, z) = ((a as f32 + 0.5) * v, (b as f32 + 0.5) * v);
            // Down, never up: the visible top never stands above the smooth ground players
            // walk on, so nothing (the road, a tree's foot) is buried by a rounded-up step.
            tops[b * n + a] = (t.sample(x, z) / v).floor() as i32;
            let dx = t.sample(x + v, z) - t.sample(x - v, z);
            let dz = t.sample(x, z + v) - t.sample(x, z - v);
            let steep = (dx * dx + dz * dz).sqrt() / (2.0 * v) > t.steep_slope;
            colours[b * n + a] = if steep { t.steep } else { t.colour(x, z, a, b) };
        }
    }
    (tops, colours)
}

/// How open each top's four corners are: a neighbour column is in the layer above the top
/// when it stands higher. Columns one past each edge are sampled, so corners at the tile's
/// edge see their neighbours.
fn top_levels(t: &Tile, tops: &[i32]) -> Vec<[u8; 4]> {
    let (n, v) = (t.n, t.voxel);
    let top_at = |a: i64, b: i64| -> i32 {
        let inside = (0..n as i64).contains(&a) && (0..n as i64).contains(&b);
        if inside {
            tops[b as usize * n + a as usize]
        } else {
            (t.sample((a as f32 + 0.5) * v, (b as f32 + 0.5) * v) / v).floor() as i32
        }
    };
    (0..n * n)
        .map(|i| {
            let (a, b) = ((i % n) as i64, (i / n) as i64);
            let up = |da: i64, db: i64| top_at(a + da, b + db) > tops[i];
            [(-1, -1), (1, -1), (1, 1), (-1, 1)]
                .map(|(da, db): (i64, i64)| corner_level(up(da, 0), up(0, db), up(da, db)))
        })
        .collect()
}

/// Tops, merged greedily by height, colour and corner levels.
fn push_tops(out: &mut Mesh, t: &Tile, tops: &[i32], colours: &[Colour], levels: &[[u8; 4]]) {
    let (n, v) = (t.n, t.voxel);
    let key = |i: usize| (tops[i], colours[i], levels[i]);
    let mut done = vec![false; n * n];
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
            out.push_quad(
                [a as f32 * v, tops[i] as f32 * v, b as f32 * v],
                [w as f32 * v, 0.0, 0.0],
                [0.0, 0.0, h as f32 * v],
                [0.0, 1.0, 0.0],
                colours[i],
                levels[i],
                true,
            );
        }
    }
}

/// Sides, where the neighbour is lower (or down a skirt at the tile edge).
fn push_sides(out: &mut Mesh, t: &Tile, tops: &[i32], colours: &[Colour]) {
    let (n, v) = (t.n, t.voxel);
    let skirt = (t.skirt / v).ceil() as i32;
    for b in 0..n {
        for a in 0..n {
            let top = tops[b * n + a];
            let neighbours: [(i64, i64, [f32; 3]); 4] = [
                (a as i64 - 1, b as i64, [-1.0, 0.0, 0.0]),
                (a as i64 + 1, b as i64, [1.0, 0.0, 0.0]),
                (a as i64, b as i64 - 1, [0.0, 0.0, -1.0]),
                (a as i64, b as i64 + 1, [0.0, 0.0, 1.0]),
            ];
            for (na, nb, normal) in neighbours {
                let inside = (0..n as i64).contains(&na) && (0..n as i64).contains(&nb);
                let low = if inside {
                    tops[nb as usize * n + na as usize]
                } else {
                    top - skirt
                };
                if low >= top {
                    continue;
                }
                // Small steps are the ground's own colour in shade; only real walls show soil,
                // or every gentle slope would read brown from a distance.
                let colour = if top - low <= 2 {
                    shade(colours[b * n + a])
                } else {
                    t.side
                };
                side_quad(out, a, b, v, low, top, normal, colour);
            }
        }
    }
}

fn shade(c: Colour) -> Colour {
    let ch = |shift: u32| (((c >> shift) & 0xFF) as f32 * 0.72) as u32;
    (ch(16) << 16) | (ch(8) << 8) | ch(0)
}

#[allow(clippy::too_many_arguments)]
fn side_quad(
    out: &mut Mesh,
    a: usize,
    b: usize,
    v: f32,
    low: i32,
    top: i32,
    normal: [f32; 3],
    colour: Colour,
) {
    let (x0, z0) = (a as f32 * v, b as f32 * v);
    let (y0, y1) = (low as f32 * v, top as f32 * v);
    let height = [0.0, y1 - y0, 0.0];
    // The winding flag is set so each wall's front face points along its normal (push_quad's
    // `back` means du x dv points against it).
    match normal {
        [x, _, _] if x < 0.0 => out.push_quad(
            [x0, y0, z0],
            [0.0, 0.0, v],
            height,
            normal,
            colour,
            [OPEN; 4],
            false,
        ),
        [x, _, _] if x > 0.0 => out.push_quad(
            [x0 + v, y0, z0],
            [0.0, 0.0, v],
            height,
            normal,
            colour,
            [OPEN; 4],
            true,
        ),
        [_, _, z] if z < 0.0 => out.push_quad(
            [x0, y0, z0],
            [v, 0.0, 0.0],
            height,
            normal,
            colour,
            [OPEN; 4],
            true,
        ),
        _ => out.push_quad(
            [x0, y0, z0 + v],
            [v, 0.0, 0.0],
            height,
            normal,
            colour,
            [OPEN; 4],
            false,
        ),
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
        let m = mesh(&tile(&heights, 3, &colours));
        let walls_facing_left = m.normals.iter().filter(|n| n[0] < -0.5).count() / 4;
        assert!(walls_facing_left >= 16, "{walls_facing_left}");
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
}
