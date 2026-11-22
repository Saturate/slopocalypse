//! Roads, tracks, lanes and levelled pads as the voxel ground sees them. Road and track strips
//! are models of their own laid over the ground: the ground beside them tilts to meet their
//! edge and stays just under them, and along a track's frayed edge it comes up to just under
//! its surface, so no side face shows. Lanes have no model: they are painted into the
//! ground's own columns. Pads only make the banks round them tilt.

use crate::{Colour, hash};

/// Floats per way segment: ax, az, ay, bx, bz, by (tile-local metres, the heights its surface
/// runs at), half width, kind (see `Kind`, plus `START_ENDS` and `END_ENDS`).
pub const WAY_STRIDE: usize = 8;
const KIND_BITS: i32 = 7;
/// Added to a segment's kind when its way ends at its first point (`START_ENDS`) or its last
/// (`END_ENDS`): a strip ends square there, flush with its model's end, instead of running
/// on round under the next segment.
pub const START_ENDS: i32 = 8;
pub const END_ENDS: i32 = 16;

/// Verges are drawn only on voxels this small or smaller; on coarser ones one cell is metres
/// wide.
const VERGE_VOXEL: f32 = 0.5;
/// Lane ruts: their middles at this share of the half width either side, this wide (as a
/// track strip's, VoxRoad RUT_AT and RUT_WIDTH).
const RUT_AT: f32 = 0.45;
const RUT_WIDTH: f32 = 0.4;
/// Ground under a strip's edge stays this far under the way's height; under a paved road's
/// middle this far, below its whole gravel bed, so a pothole or a blast through it shows the
/// bed's depth and not a flat disc of ground.
const UNDER_STRIP: f32 = 0.02;
const UNDER_PAVED: f32 = 0.3;
/// Along a track's frayed edge the ground comes up to this far under the strip's surface on
/// coarse tiles, and this far over it on fine ones: there the ground itself draws the frayed
/// edge, and the strip's own ragged cells (whose ends would show as dark notches) stay
/// under it.
const UNDER_FRAY: f32 = 0.01;
const OVER_FRAY: f32 = 0.005;
/// Tiles with voxels this small or smaller draw a track's frayed edge in the ground.
pub const FINE_VOXEL: f32 = 0.5;
/// Ground at most this far under a frayed edge is lifted to it.
const LIFT_MOST: f32 = 0.15;
/// Strips hold the ground this far past their edge, the same at every level of detail so
/// neighbouring tiles agree; under the earthworks' 1.5 m shoulder, which is level with the
/// way, so a bank beyond is never pulled down.
pub const HOLD: f32 = 1.0;
/// A track's frayed edge wanders over this many metres from one high or low to the next.
const FRAY_METRES: f32 = 1.2;
/// A lane's edge wanders over this many cells from one high or low to the next.
const WANDER_CELLS: f32 = 6.0;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    /// A paved road strip: kerbs, lines, a gravel bed.
    Paved,
    /// A dirt track strip: no kerb, a frayed edge.
    Track,
    /// A painted lane with round ends, worn into two ruts.
    Lane,
    /// A painted lane with square ends and no ruts (a site's yard).
    Yard,
    /// A levelled pad (square ends, its level as the height): nothing drawn, its banks tilt.
    Pad,
}

impl Kind {
    fn of(code: f32) -> Kind {
        match code.round() as i32 & KIND_BITS {
            1 => Kind::Track,
            2 => Kind::Lane,
            3 => Kind::Yard,
            4 => Kind::Pad,
            _ => Kind::Paved,
        }
    }

    /// Drawn as a model of its own over the ground.
    pub fn is_strip(self) -> bool {
        matches!(self, Kind::Paved | Kind::Track)
    }

    fn square(self) -> bool {
        matches!(self, Kind::Yard | Kind::Pad)
    }
}

/// How the ground draws what lies on it; colours as 0xRRGGBB.
#[derive(Clone, Copy, Debug)]
pub struct Look {
    /// What shows where a strip is worn or shot through: a paved road's gravel bed, a track's
    /// soil.
    pub paved_bed: Colour,
    pub track_soil: Colour,
    /// How far a strip's surface stands over the way's height (metres).
    pub strip_top: f32,
    /// How far in from a track's edge its strip frays (metres); a lane's edge wanders out as
    /// far.
    pub track_fray: f32,
    /// Share of the cells one past a track's edge that get the verge colour.
    pub track_verge: f32,
    /// How far a yard's edge wanders out (metres), and how round its corners are.
    pub yard_fray: f32,
    pub yard_round: f32,
    /// A lane's soil and how far it is toned toward the ground under it (0 to 1).
    pub lane_soil: Colour,
    pub lane_mix: f32,
    /// A verge cell's colour lies this far from the soil toward the ground's own.
    pub verge_mix: f32,
    /// How much darker a lane's wheel ruts are than its soil, as a track strip's worn ruts.
    pub rut_dark: f32,
}

impl Default for Look {
    fn default() -> Look {
        Look {
            paved_bed: 0x78_6E_5E,
            track_soil: 0x66_4F_36,
            strip_top: 0.03,
            track_fray: 0.3,
            track_verge: 0.6,
            yard_fray: 1.0,
            yard_round: 2.0,
            lane_soil: 0x66_4F_36,
            lane_mix: 0.1,
            verge_mix: 0.5,
            rut_dark: 0.06,
        }
    }
}

/// A way near a point: how far outside its edge the point is (negative inside), how far from
/// its middle line, its half width and its height there.
#[derive(Clone, Copy, Debug)]
pub struct Near {
    pub edge: f32,
    /// How far past the nearer of its square way ends (negative inside), or -INFINITY.
    pub past_end: f32,
    pub d: f32,
    pub half: f32,
    pub h: f32,
    pub kind: Kind,
}

/// What lies at a point: the nearest strip, the nearest painted lane, the nearest pad, and
/// the height the ground there is held to by the strips over it (INFINITY when none).
#[derive(Clone, Copy, Debug, Default)]
pub struct Scan {
    pub strip: Option<Near>,
    pub lane: Option<Near>,
    pub pad: Option<Near>,
    /// The lowest a strip holds the ground down to here.
    pub cap: f32,
    /// The highest a track's frayed edge lifts the ground to here (where two meet, the
    /// higher one's edge is the one that would show).
    pub lift: f32,
}

impl Scan {
    /// The strip or lane whose edge is nearer: what paints the column.
    pub fn paint(&self) -> Option<Near> {
        match (self.strip, self.lane) {
            (Some(s), Some(l)) => Some(if l.edge < s.edge { l } else { s }),
            (s, l) => s.or(l),
        }
    }

    /// The height at a corner whose ground stands at `h`: lifted (never lowered) along a
    /// frayed edge, held down under every strip over it.
    pub fn held(&self, h: f32) -> f32 {
        // Only ground just under the edge comes up: a bank or a crater falling away from it
        // keeps its shape.
        let lifted = if self.lift > f32::NEG_INFINITY && self.lift - h < LIFT_MOST {
            h.max(self.lift)
        } else {
            h
        };
        lifted.min(self.cap)
    }
}

struct Seg {
    a: [f32; 3],
    b: [f32; 3],
    half: f32,
    kind: Kind,
    /// Its ends that are its way's ends (square), and how round a square kind's corners are.
    ends: [bool; 2],
    round: f32,
    /// Its box (x, z) grown by how far anything asks about it.
    lo: [f32; 2],
    hi: [f32; 2],
}

/// The ways over one tile, each with a box, so a point only measures the few near it.
pub struct Ways {
    segs: Vec<Seg>,
    /// The tile's voxel size: a fine tile draws a track's frayed edge in the ground over the
    /// strip, a column further in than the fray so no frayed cell's end stands out of it.
    pub voxel: f32,
}

impl Ways {
    /// The ways among `raw` (`WAY_STRIDE` floats each) whose box, grown by their half width
    /// and `reach` (strips and lanes) or `pad_reach` (pads), touches the tile `size` metres
    /// a side. Yards get corners `round` metres round.
    pub fn new(raw: &[f32], reach: f32, pad_reach: f32, size: f32, round: f32) -> Ways {
        let segs = raw
            .chunks_exact(WAY_STRIDE)
            .filter_map(|s| {
                let kind = Kind::of(s[7]);
                let grow = s[6] + if kind == Kind::Pad { pad_reach } else { reach };
                let lo = [s[0].min(s[3]) - grow, s[1].min(s[4]) - grow];
                let hi = [s[0].max(s[3]) + grow, s[1].max(s[4]) + grow];
                let touches = hi[0] >= 0.0 && hi[1] >= 0.0 && lo[0] <= size && lo[1] <= size;
                let code = s[7].round() as i32;
                touches.then_some(Seg {
                    a: [s[0], s[1], s[2]],
                    b: [s[3], s[4], s[5]],
                    half: s[6],
                    kind,
                    ends: [code & START_ENDS != 0, code & END_ENDS != 0],
                    round: if kind == Kind::Yard {
                        round.min(s[6])
                    } else {
                        0.0
                    },
                    lo,
                    hi,
                })
            })
            .collect();
        Ways { segs, voxel: 1.0 }
    }

    pub fn is_empty(&self) -> bool {
        self.segs.is_empty()
    }

    /// What lies at (x, z). Strips hold corners within `near` metres of their edge (`HOLD`),
    /// so a coarse tile's corner just past the edge never stands over them.
    pub fn scan(&self, look: &Look, x: f32, z: f32, near: f32) -> Scan {
        let mut out = Scan {
            cap: f32::INFINITY,
            lift: f32::NEG_INFINITY,
            ..Scan::default()
        };
        for s in &self.segs {
            if x < s.lo[0] || x > s.hi[0] || z < s.lo[1] || z > s.hi[1] {
                continue;
            }
            let r = measure(s, x, z);
            let slot = match s.kind {
                Kind::Paved | Kind::Track => &mut out.strip,
                Kind::Lane | Kind::Yard => &mut out.lane,
                Kind::Pad => &mut out.pad,
            };
            if slot.is_none_or(|b| r.edge < b.edge) {
                *slot = Some(r);
            }
            if !s.kind.is_strip() || r.edge >= near {
                continue;
            }
            let fine = self.voxel <= FINE_VOXEL;
            // A strip's square end is covered a column deep, so its end face never shows.
            let at_end = r.past_end > -self.voxel - 0.05;
            if fine
                && s.kind == Kind::Track
                && (r.edge > -look.track_fray * fray_at(x, z) || at_end)
            {
                out.lift = out.lift.max(r.h + look.strip_top + OVER_FRAY);
            } else if !fine && s.kind == Kind::Track && r.edge > -look.track_fray - near {
                out.lift = out.lift.max(r.h + look.strip_top - UNDER_FRAY);
            } else if s.kind == Kind::Paved && r.edge < -near {
                out.cap = out.cap.min(r.h - UNDER_PAVED);
            } else {
                out.cap = out.cap.min(r.h - UNDER_STRIP);
            }
        }
        out
    }
}

fn measure(s: &Seg, x: f32, z: f32) -> Near {
    let (ax, az, ay) = (s.a[0], s.a[1], s.a[2]);
    let (dx, dz) = (s.b[0] - ax, s.b[1] - az);
    let len2 = (dx * dx + dz * dz).max(1e-6);
    let raw = ((x - ax) * dx + (z - az) * dz) / len2;
    let k = raw.clamp(0.0, 1.0);
    let (px, pz) = (ax + dx * k, az + dz * k);
    let mut d = ((x - px) * (x - px) + (z - pz) * (z - pz)).sqrt();
    let len = len2.sqrt();
    let past_end = if s.ends[0] && raw < 0.5 {
        -raw * len
    } else if s.ends[1] && raw >= 0.5 {
        (raw - 1.0) * len
    } else {
        f32::NEG_INFINITY
    };
    let square = s.kind.square() || (raw < 0.0 && s.ends[0]) || (raw > 1.0 && s.ends[1]);
    if square {
        // A rectangle with corners `round` round: as far out as the further of its sides
        // and ends, measured round the corners.
        let len = len2.sqrt();
        let past = (-raw).max(raw - 1.0) * len;
        let across = ((x - ax) * dz - (z - az) * dx).abs() / len;
        let (qx, qz) = (across - s.half + s.round, past + s.round);
        let outside = (qx.max(0.0).powi(2) + qz.max(0.0).powi(2)).sqrt();
        d = s.half + outside + qx.max(qz).min(0.0) - s.round;
    }
    Near {
        edge: d - s.half,
        past_end,
        d,
        half: s.half,
        h: ay + (s.b[2] - ay) * k,
        kind: s.kind,
    }
}

/// How far in a track's frayed edge comes at (x, z), as a share of the fray: a smooth noise
/// over metres, so the ground's edge over the strip wanders like worn grass.
fn fray_at(x: f32, z: f32) -> f32 {
    let (fx, fz) = (x / FRAY_METRES + 1000.0, z / FRAY_METRES + 1000.0);
    let (ix, iz) = (fx.floor(), fz.floor());
    let (tx, tz) = (fx - ix, fz - iz);
    let ease = |t: f32| t * t * (3.0 - 2.0 * t);
    let at = |dx: u32, dz: u32| hash(ix as u32 + dx, iz as u32 + dz, 37, 0);
    let lo = at(0, 0) + (at(1, 0) - at(0, 0)) * ease(tx);
    let hi = at(0, 1) + (at(1, 1) - at(0, 1)) * ease(tx);
    lo + (hi - lo) * ease(tz)
}

/// A smooth value noise over the cell grid, 0 to 1.
fn wander(a: usize, b: usize, seed: u32) -> f32 {
    let (x, z) = (a as f32 / WANDER_CELLS, b as f32 / WANDER_CELLS);
    let (ix, iz) = (x.floor(), z.floor());
    let (tx, tz) = (x - ix, z - iz);
    let ease = |t: f32| t * t * (3.0 - 2.0 * t);
    let at = |dx: u32, dz: u32| hash(ix as u32 + dx, iz as u32 + dz, 31, seed);
    let lo = at(0, 0) + (at(1, 0) - at(0, 0)) * ease(tx);
    let hi = at(0, 1) + (at(1, 1) - at(0, 1)) * ease(tx);
    lo + (hi - lo) * ease(tz)
}

pub fn mix(a: Colour, b: Colour, k: f32) -> Colour {
    let ch = |c: Colour, s: u32| ((c >> s) & 0xFF) as f32;
    let m = |s: u32| {
        ((ch(a, s) + (ch(b, s) - ch(a, s)) * k)
            .round()
            .clamp(0.0, 255.0) as u32)
            << s
    };
    m(16) | m(8) | m(0)
}

/// A column a way may paint: its place on the voxel grid (`a`, `b`), the voxel's size, its own
/// colour and whether a crater has been dug there.
pub struct Column {
    pub a: usize,
    pub b: usize,
    pub voxel: f32,
    pub ground: Colour,
    pub dug: bool,
    pub seed: u32,
}

/// The colour a column takes from the way `r` nearest it, or None where its own shows (a dug
/// crater keeps its earth).
pub fn colour(look: &Look, r: &Near, c: &Column) -> Option<Colour> {
    if c.dug {
        return None;
    }
    let v = c.voxel;
    let jit = hash(c.a as u32, c.b as u32, 23, c.seed);
    match r.kind {
        Kind::Pad => None,
        Kind::Paved => (r.edge < -v).then_some(look.paved_bed),
        Kind::Track => {
            let verge = mix(look.track_soil, c.ground, look.verge_mix);
            // The frayed edge: the ground comes up over the strip's edge by a wandering
            // amount (see `Ways::scan`), drawn as verge; under the strip, its soil.
            let (x, z) = ((c.a as f32 + 0.5) * v, (c.b as f32 + 0.5) * v);
            if r.edge < -look.track_fray * fray_at(x, z) {
                Some(look.track_soil)
            } else if r.edge < 0.0 {
                Some(verge)
            } else {
                (r.edge < v && v <= VERGE_VOXEL && jit < look.track_verge).then_some(verge)
            }
        }
        Kind::Lane | Kind::Yard => {
            let dirt = mix(look.lane_soil, c.ground, look.lane_mix);
            // The edge wanders out smoothly, a value noise over the cells, so it reads as
            // worn ground rather than a drawn line.
            let most = if r.kind == Kind::Yard {
                look.yard_fray
            } else {
                look.track_fray
            };
            let edge = r.edge - wander(c.a, c.b, c.seed) * most;
            if edge >= 0.0 {
                return (edge < v).then(|| mix(dirt, c.ground, look.verge_mix));
            }
            let rut =
                r.kind == Kind::Lane && (r.d - r.half * RUT_AT).abs() < v.max(RUT_WIDTH) / 2.0;
            Some(if rut {
                mix(dirt, 0, look.rut_dark)
            } else {
                dirt
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ways(raw: &[f32]) -> Ways {
        Ways::new(raw, 5.0, 5.0, 32.0, 0.0)
    }

    #[test]
    fn a_yard_ends_square_and_a_lane_round() {
        let lane = [0.0, 0.0, 0.0, 10.0, 0.0, 0.0, 2.0, 2.0];
        let mut yard = lane;
        yard[7] = 3.0;
        let look = Look::default();
        // Just past the end, beside the middle line by most of the half width.
        let (x, z) = (10.5, 1.99);
        assert!(ways(&lane).scan(&look, x, z, 0.5).lane.unwrap().edge > 0.0);
        assert!((ways(&yard).scan(&look, x, z, 0.5).lane.unwrap().edge - 0.5).abs() < 1e-3);
        assert!(ways(&yard).scan(&look, 9.0, 1.0, 0.5).lane.unwrap().edge < 0.0);
    }

    #[test]
    fn strips_lanes_and_pads_are_told_apart() {
        let raw = [
            0.0, 0.0, 0.0, 10.0, 0.0, 0.0, 2.0, 0.0, //
            0.0, 3.0, 0.0, 10.0, 3.0, 0.0, 1.0, 2.0, //
            0.0, 9.0, 0.0, 10.0, 9.0, 0.0, 1.0, 4.0,
        ];
        let s = ways(&raw).scan(&Look::default(), 5.0, 5.0, 0.5);
        assert_eq!(s.strip.unwrap().kind, Kind::Paved);
        assert_eq!(s.lane.unwrap().kind, Kind::Lane);
        assert_eq!(s.pad.unwrap().kind, Kind::Pad);
        // The lane's edge is nearer; it paints.
        assert_eq!(s.paint().unwrap().kind, Kind::Lane);
    }

    #[test]
    fn overlapping_strips_hold_the_ground_under_the_lowest() {
        // Two strips crossing at different heights.
        let raw = [
            0.0, 5.0, 1.0, 10.0, 5.0, 1.0, 2.0, 0.0, //
            5.0, 0.0, 0.6, 5.0, 10.0, 0.6, 2.0, 0.0,
        ];
        let s = ways(&raw).scan(&Look::default(), 5.0, 5.0, 0.5);
        assert!((s.held(3.0) - (0.6 - UNDER_PAVED)).abs() < 1e-5);
        // Under one only, its own.
        let s = ways(&raw).scan(&Look::default(), 1.0, 5.0, 0.5);
        assert!((s.held(3.0) - (1.0 - UNDER_PAVED)).abs() < 1e-5);
    }

    #[test]
    fn a_tracks_frayed_edge_lifts_the_ground_to_just_under_its_surface() {
        let raw = [0.0, 5.0, 1.0, 10.0, 5.0, 1.0, 2.0, 1.0];
        let look = Look::default();
        let w = ways(&raw);
        let edge = w.scan(&look, 5.0, 5.0 + 2.1, 0.5);
        assert!((edge.held(0.9) - (1.0 + look.strip_top - UNDER_FRAY)).abs() < 1e-5);
        // A fine tile draws the edge in the ground, just over the strip.
        let mut fine = ways(&raw);
        fine.voxel = 0.25;
        let over = fine.scan(&look, 5.0, 5.0 + 2.0, 0.5);
        assert!((over.held(0.9) - (1.0 + look.strip_top + OVER_FRAY)).abs() < 1e-5);
        assert!(fine.scan(&look, 5.0, 5.0 + 1.3, 0.5).held(1.0) < 1.0);
        let middle = w.scan(&look, 5.0, 5.0, 0.5);
        assert!((middle.held(1.0) - (1.0 - UNDER_STRIP)).abs() < 1e-5);
        // Well past the edge, untouched.
        assert_eq!(w.scan(&look, 5.0, 5.0 + 3.0, 0.5).held(0.7), 0.7);
    }

    #[test]
    fn ways_far_from_the_tile_are_dropped() {
        let raw = [100.0, 100.0, 0.0, 110.0, 100.0, 0.0, 2.0, 0.0];
        assert!(ways(&raw).is_empty());
    }

    #[test]
    fn a_dug_column_keeps_its_own_colour() {
        let r = Near {
            edge: -1.0,
            past_end: f32::NEG_INFINITY,
            d: 0.5,
            half: 1.5,
            h: 0.0,
            kind: Kind::Lane,
        };
        let mut c = Column {
            a: 3,
            b: 4,
            voxel: 0.25,
            ground: 0x00FF00,
            dug: false,
            seed: 1,
        };
        assert!(colour(&Look::default(), &r, &c).is_some());
        c.dug = true;
        assert!(colour(&Look::default(), &r, &c).is_none());
    }

    #[test]
    fn a_strip_ends_square_where_its_way_ends() {
        let look = Look::default();
        let round = [0.0, 5.0, 0.0, 10.0, 5.0, 0.0, 2.0, 0.0];
        let mut flush = round;
        flush[7] = END_ENDS as f32;
        // Past the end, beside the middle line: inside a round end, outside a square one.
        let (x, z) = (10.5, 5.5);
        assert!(ways(&round).scan(&look, x, z, 0.5).strip.unwrap().edge < 0.0);
        assert!((ways(&flush).scan(&look, x, z, 0.5).strip.unwrap().edge - 0.5).abs() < 1e-4);
        // The start stays round.
        assert!(ways(&flush).scan(&look, -0.5, 5.5, 0.5).strip.unwrap().edge < 0.0);
    }

    #[test]
    fn a_yards_corners_are_round() {
        let look = Look::default();
        let yard = [0.0, 5.0, 0.0, 10.0, 5.0, 0.0, 4.0, 3.0];
        let w = Ways::new(&yard, 5.0, 5.0, 32.0, 2.0);
        // Just inside the square corner, outside the round one.
        assert!(w.scan(&look, 9.9, 8.9, 0.5).lane.unwrap().edge > 0.0);
        // Along a side, as a rectangle.
        assert!((w.scan(&look, 5.0, 9.5, 0.5).lane.unwrap().edge - 0.5).abs() < 1e-4);
    }
}
