//! Rules for mission zones that must come out the same on every machine.

use std::collections::VecDeque;

/// Which standing segments of a building nothing holds up any more.
///
/// Segments are graph nodes; `edges` connects segments that share a face or an edge.
/// `anchors` stand on the ground (the lower row of wall). A wall segment is held when a path
/// of standing wall segments leads to a standing anchor. A roof segment is held when it
/// touches a held wall, or is at most `max_span` roof steps from one that does, so losing
/// one wall piece leaves the roof up but losing most of a wall brings its edge down. A wall
/// segment hanging from a held roof stays too. Everything else standing is returned, in id
/// order.
pub fn unsupported(
    roof: &[bool],
    edges: &[(usize, usize)],
    anchors: &[usize],
    broken: &[usize],
    max_span: usize,
) -> Vec<usize> {
    let n = roof.len();
    let standing = standing_mask(n, broken);
    let next = neighbours(n, edges);
    let wall = |i: usize| standing[i] && !roof[i];
    // Walls held up from the ground.
    let mut held = vec![false; n];
    let mut queue: VecDeque<usize> = anchors
        .iter()
        .copied()
        .filter(|&a| a < n && wall(a))
        .collect();
    for &a in &queue {
        held[a] = true;
    }
    spread(&mut held, &mut queue, &next, wall);
    // Roof pieces within `max_span` roof steps of a held wall.
    let steps = roof_steps(&next, &held, |i| standing[i] && roof[i]);
    for i in (0..n).filter(|&i| steps[i] <= max_span) {
        held[i] = true;
        queue.push_back(i);
    }
    // Walls hanging from a held roof.
    spread(&mut held, &mut queue, &next, wall);
    (0..n).filter(|&i| standing[i] && !held[i]).collect()
}

/// Which standing segments are carrying more than they can, worked out by passing weight
/// down to the ground.
///
/// Every standing segment rests on its standing neighbours that are one step nearer a standing
/// anchor (counted over standing segments). Starting from the furthest, each hands its own
/// `mass` plus everything resting on it to those neighbours, split evenly. A segment whose
/// load (what rests on it, not counting itself) is more than its `strength` gives way.
/// Segments with no path to an anchor carry nothing here (`unsupported` deals with those).
/// Returned in id order.
pub fn overloaded(
    edges: &[(usize, usize)],
    anchors: &[usize],
    broken: &[usize],
    mass: &[f32],
    strength: &[f32],
) -> Vec<usize> {
    let n = mass.len().min(strength.len());
    let standing = standing_mask(n, broken);
    let next = neighbours(n, edges);
    // Steps to the nearest standing anchor, over standing segments.
    let mut steps = vec![usize::MAX; n];
    let mut queue: VecDeque<usize> = anchors
        .iter()
        .copied()
        .filter(|&a| a < n && standing[a])
        .collect();
    for &a in &queue {
        steps[a] = 0;
    }
    while let Some(i) = queue.pop_front() {
        for &j in &next[i] {
            if standing[j] && steps[j] == usize::MAX {
                steps[j] = steps[i] + 1;
                queue.push_back(j);
            }
        }
    }
    let mut order: Vec<usize> = (0..n).filter(|&i| steps[i] != usize::MAX).collect();
    // Furthest first, so every segment has all its load before it hands it on; ties by id
    // so it comes out the same everywhere.
    order.sort_by(|&a, &b| steps[b].cmp(&steps[a]).then(a.cmp(&b)));
    let mut load = vec![0.0f32; n];
    for &i in &order {
        if steps[i] == 0 {
            continue;
        }
        let below: Vec<usize> = next[i]
            .iter()
            .copied()
            .filter(|&j| steps[j] != usize::MAX && steps[j] + 1 == steps[i])
            .collect();
        let share = (mass[i] + load[i]) / below.len().max(1) as f32;
        for j in below {
            load[j] += share;
        }
    }
    (0..n)
        .filter(|&i| steps[i] != usize::MAX && load[i] > strength[i])
        .collect()
}

fn standing_mask(n: usize, broken: &[usize]) -> Vec<bool> {
    let mut standing = vec![true; n];
    for &b in broken.iter().filter(|&&b| b < n) {
        standing[b] = false;
    }
    standing
}

/// Each segment's connected segments, ignoring ids out of range and self-loops.
fn neighbours(n: usize, edges: &[(usize, usize)]) -> Vec<Vec<usize>> {
    let mut next: Vec<Vec<usize>> = vec![Vec::new(); n];
    for &(a, b) in edges.iter().filter(|&&(a, b)| a < n && b < n && a != b) {
        next[a].push(b);
        next[b].push(a);
    }
    next
}

/// Roof steps from the nearest held wall for every standing roof piece (`usize::MAX` where no
/// path leads to one): 0 for a piece touching a held wall, one more per roof piece crossed.
fn roof_steps(next: &[Vec<usize>], held: &[bool], is_roof: impl Fn(usize) -> bool) -> Vec<usize> {
    let mut steps = vec![usize::MAX; next.len()];
    let mut queue: VecDeque<usize> = (0..next.len())
        .filter(|&i| is_roof(i) && next[i].iter().any(|&j| held[j] && !is_roof(j)))
        .collect();
    for &i in &queue {
        steps[i] = 0;
    }
    while let Some(i) = queue.pop_front() {
        for &j in &next[i] {
            if is_roof(j) && steps[j] == usize::MAX {
                steps[j] = steps[i] + 1;
                queue.push_back(j);
            }
        }
    }
    steps
}

/// Marks everything reachable from `queue` through nodes `can` accepts.
fn spread(
    held: &mut [bool],
    queue: &mut VecDeque<usize>,
    next: &[Vec<usize>],
    can: impl Fn(usize) -> bool,
) {
    while let Some(i) = queue.pop_front() {
        for &j in &next[i] {
            if !held[j] && can(j) {
                held[j] = true;
                queue.push_back(j);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// One straight wall `cols` segments long, two rows high, with a roof strip `depth`
    /// segments deep on top of it (only the first roof row rests on the wall). Ids: lower row
    /// 0..cols, upper row cols..2*cols, roof 2*cols.. row by row.
    struct Shed {
        roof: Vec<bool>,
        edges: Vec<(usize, usize)>,
        anchors: Vec<usize>,
        cols: usize,
    }

    impl Shed {
        fn new(cols: usize, depth: usize) -> Shed {
            let walls = 2 * cols;
            let mut roof = vec![false; walls];
            roof.extend(std::iter::repeat_n(true, cols * depth));
            let mut edges = Vec::new();
            for c in 0..cols {
                edges.push((c, cols + c));
                if c + 1 < cols {
                    edges.push((c, c + 1));
                    edges.push((cols + c, cols + c + 1));
                }
                edges.push((cols + c, walls + c));
                for r in 0..depth {
                    let id = walls + r * cols + c;
                    if c + 1 < cols {
                        edges.push((id, id + 1));
                    }
                    if r + 1 < depth {
                        edges.push((id, id + cols));
                    }
                }
            }
            Shed {
                roof,
                edges,
                anchors: (0..cols).collect(),
                cols,
            }
        }

        fn lower(&self, c: usize) -> usize {
            c
        }

        fn upper(&self, c: usize) -> usize {
            self.cols + c
        }

        fn roof(&self, row: usize, c: usize) -> usize {
            2 * self.cols + row * self.cols + c
        }

        fn fall(&self, broken: &[usize], max_span: usize) -> Vec<usize> {
            unsupported(&self.roof, &self.edges, &self.anchors, broken, max_span)
        }
    }

    /// A tower: `legs` columns of `height` segments, all joined at the top by one deck segment
    /// per leg in a ring. Ids: leg l level h is l * height + h; deck pieces after the legs.
    fn tower(legs: usize, height: usize) -> (Vec<(usize, usize)>, Vec<usize>, usize) {
        let mut edges = Vec::new();
        for l in 0..legs {
            for h in 0..height - 1 {
                edges.push((l * height + h, l * height + h + 1));
            }
        }
        let deck = legs * height;
        for l in 0..legs {
            edges.push((l * height + height - 1, deck + l));
            edges.push((deck + l, deck + (l + 1) % legs));
        }
        let anchors = (0..legs).map(|l| l * height).collect();
        (edges, anchors, deck + legs)
    }

    #[test]
    fn a_whole_tower_stands_and_one_leg_alone_does_not() {
        let (edges, anchors, n) = tower(4, 3);
        let mass = vec![10.0; n];
        // Each piece carries up to six times a piece's weight.
        let strength = vec![60.0; n];
        assert!(overloaded(&edges, &anchors, &[], &mass, &strength).is_empty());
        // Three legs cut at the bottom: the last leg carries the whole deck and the others' tops.
        let cut = [3, 6, 9];
        let over = overloaded(&edges, &anchors, &cut, &mass, &strength);
        assert!(over.contains(&0), "the last leg's foot gives way: {over:?}");
    }

    #[test]
    fn stronger_stuff_holds_what_weaker_stuff_cannot() {
        let (edges, anchors, n) = tower(4, 3);
        let mass = vec![10.0; n];
        let cut = [3, 6, 9];
        assert!(!overloaded(&edges, &anchors, &cut, &mass, &vec![60.0; n]).is_empty());
        assert!(overloaded(&edges, &anchors, &cut, &mass, &vec![1000.0; n]).is_empty());
    }

    #[test]
    fn a_house_on_one_corner_piece_loses_it_but_a_whole_one_stands() {
        let shed = Shed::new(6, 3);
        let n = shed.roof.len();
        let mass = vec![10.0; n];
        let strength = vec![80.0; n];
        assert!(overloaded(&shed.edges, &shed.anchors, &[], &mass, &strength).is_empty());
        // Everything but the first column of wall gone: it carries the whole roof.
        let mut broken: Vec<usize> = (1..6).map(|c| shed.lower(c)).collect();
        broken.extend((1..6).map(|c| shed.upper(c)));
        let over = overloaded(&shed.edges, &shed.anchors, &broken, &mass, &strength);
        assert!(over.contains(&shed.lower(0)), "{over:?}");
    }

    #[test]
    fn a_whole_building_stands() {
        let s = Shed::new(4, 3);
        assert!(s.fall(&[], 2).is_empty());
    }

    #[test]
    fn breaking_the_lower_row_of_a_whole_wall_drops_what_is_above() {
        let s = Shed::new(3, 1);
        let broken: Vec<usize> = (0..3).map(|c| s.lower(c)).collect();
        let fell = s.fall(&broken, 2);
        for c in 0..3 {
            assert!(fell.contains(&s.upper(c)));
            assert!(fell.contains(&s.roof(0, c)));
        }
    }

    #[test]
    fn one_wall_segment_under_a_roof_drops_nothing() {
        let s = Shed::new(5, 2);
        assert!(s.fall(&[s.lower(2)], 2).is_empty());
        assert!(s.fall(&[s.lower(2), s.upper(2)], 2).is_empty());
    }

    #[test]
    fn roof_further_than_max_span_from_a_held_wall_falls() {
        let s = Shed::new(7, 1);
        // Columns 1..=6 of the wall gone (both rows): the roof over them hangs from column 0.
        let mut broken = Vec::new();
        for c in 1..7 {
            broken.push(s.lower(c));
            broken.push(s.upper(c));
        }
        let fell = s.fall(&broken, 2);
        // Roof over columns 1 and 2 is within 2 steps of the roof on column 0; the rest is not.
        assert!(!fell.contains(&s.roof(0, 0)));
        assert!(!fell.contains(&s.roof(0, 1)));
        assert!(!fell.contains(&s.roof(0, 2)));
        for c in 3..7 {
            assert!(
                fell.contains(&s.roof(0, c)),
                "roof over column {c} should fall"
            );
        }
        // A wider span keeps more of it up.
        assert!(!s.fall(&broken, 3).contains(&s.roof(0, 3)));
    }

    #[test]
    fn a_long_path_to_an_anchor_holds() {
        let s = Shed::new(12, 1);
        // Only the first lower segment still touches the ground; the upper row carries the
        // rest across the gap.
        let broken: Vec<usize> = (1..12).map(|c| s.lower(c)).collect();
        assert!(s.fall(&broken, 2).is_empty());
    }

    #[test]
    fn a_wall_piece_hanging_from_a_held_roof_stays() {
        let s = Shed::new(5, 1);
        // The middle upper piece lost everything below and beside it, but the roof above it
        // is held from both ends, so it hangs there.
        let broken = [s.lower(2), s.upper(1), s.upper(3)];
        assert!(s.fall(&broken, 2).is_empty());
        // With the roof span too short to reach it, it comes down with the roof.
        let fell = s.fall(&broken, 1);
        assert!(fell.contains(&s.upper(2)));
        assert!(fell.contains(&s.roof(0, 2)));
    }

    #[test]
    fn bad_ids_are_ignored() {
        let s = Shed::new(2, 1);
        let fell = unsupported(&s.roof, &[(0, 99), (0, 0)], &[0, 77], &[55], 2);
        // Only segment 0 is anchored and nothing connects to it.
        assert_eq!(fell, vec![1, 2, 3, 4, 5]);
    }
}
