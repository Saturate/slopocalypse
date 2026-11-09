//! Grid inventory: items take a w x h block of cells, can be turned 90
//! degrees, and may not overlap or leave the grid. Pure rules so the server (which decides)
//! and the client (which previews a drag) agree.

use std::collections::BTreeMap;

/// Cells an item takes when not rotated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Size {
    pub w: u8,
    pub h: u8,
}

impl Size {
    pub fn turned(self, rotated: bool) -> Size {
        if rotated {
            Size {
                w: self.h,
                h: self.w,
            }
        } else {
            self
        }
    }
}

/// One item in the grid. `uid` is unique per item instance; `item` names its definition.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Placed {
    pub uid: u32,
    pub item: String,
    pub x: u8,
    pub y: u8,
    pub rotated: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlaceError {
    UnknownItem(String),
    OutOfBounds,
    Overlaps(u32),
    NoSuchUid(u32),
    DuplicateUid(u32),
    NoRoom,
}

impl std::fmt::Display for PlaceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnknownItem(id) => write!(f, "unknown item '{id}'"),
            Self::OutOfBounds => write!(f, "does not fit inside the grid there"),
            Self::Overlaps(uid) => write!(f, "overlaps item {uid}"),
            Self::NoSuchUid(uid) => write!(f, "no item {uid} here"),
            Self::DuplicateUid(uid) => write!(f, "item {uid} is already here"),
            Self::NoRoom => write!(f, "no room for it"),
        }
    }
}

/// Item id -> size.
pub type Sizes = BTreeMap<String, Size>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Grid {
    pub w: u8,
    pub h: u8,
    items: Vec<Placed>,
}

impl Grid {
    pub fn new(w: u8, h: u8) -> Self {
        Self {
            w,
            h,
            items: Vec::new(),
        }
    }

    pub fn items(&self) -> &[Placed] {
        &self.items
    }

    pub fn get(&self, uid: u32) -> Option<&Placed> {
        self.items.iter().find(|p| p.uid == uid)
    }

    /// Whether `item` fits at (x, y), ignoring the item `moving` (the one being dragged).
    pub fn check(
        &self,
        sizes: &Sizes,
        item: &str,
        x: u8,
        y: u8,
        rotated: bool,
        moving: Option<u32>,
    ) -> Result<(), PlaceError> {
        let size = sizes
            .get(item)
            .ok_or_else(|| PlaceError::UnknownItem(item.to_string()))?
            .turned(rotated);
        if size.w == 0
            || size.h == 0
            || u16::from(x) + u16::from(size.w) > u16::from(self.w)
            || u16::from(y) + u16::from(size.h) > u16::from(self.h)
        {
            return Err(PlaceError::OutOfBounds);
        }
        for other in &self.items {
            if Some(other.uid) == moving {
                continue;
            }
            let Some(o) = sizes.get(&other.item) else {
                continue;
            };
            let o = o.turned(other.rotated);
            let apart = x + size.w <= other.x
                || other.x + o.w <= x
                || y + size.h <= other.y
                || other.y + o.h <= y;
            if !apart {
                return Err(PlaceError::Overlaps(other.uid));
            }
        }
        Ok(())
    }

    pub fn place(&mut self, sizes: &Sizes, placed: Placed) -> Result<(), PlaceError> {
        if self.get(placed.uid).is_some() {
            return Err(PlaceError::DuplicateUid(placed.uid));
        }
        self.check(
            sizes,
            &placed.item,
            placed.x,
            placed.y,
            placed.rotated,
            None,
        )?;
        self.items.push(placed);
        Ok(())
    }

    /// Moves (and maybe turns) an item already in this grid.
    pub fn move_to(
        &mut self,
        sizes: &Sizes,
        uid: u32,
        x: u8,
        y: u8,
        rotated: bool,
    ) -> Result<(), PlaceError> {
        let item = self
            .get(uid)
            .ok_or(PlaceError::NoSuchUid(uid))?
            .item
            .clone();
        self.check(sizes, &item, x, y, rotated, Some(uid))?;
        if let Some(p) = self.items.iter_mut().find(|p| p.uid == uid) {
            p.x = x;
            p.y = y;
            p.rotated = rotated;
        }
        Ok(())
    }

    pub fn remove(&mut self, uid: u32) -> Option<Placed> {
        let i = self.items.iter().position(|p| p.uid == uid)?;
        Some(self.items.remove(i))
    }

    /// The first free spot for `item`, scanning rows from the top left, upright before
    /// turned.
    pub fn find_spot(&self, sizes: &Sizes, item: &str) -> Option<(u8, u8, bool)> {
        for rotated in [false, true] {
            for y in 0..self.h {
                for x in 0..self.w {
                    if self.check(sizes, item, x, y, rotated, None).is_ok() {
                        return Some((x, y, rotated));
                    }
                }
            }
        }
        None
    }

    /// Puts `item` in the first free spot, as picking something up does.
    pub fn insert(&mut self, sizes: &Sizes, uid: u32, item: &str) -> Result<Placed, PlaceError> {
        if !sizes.contains_key(item) {
            return Err(PlaceError::UnknownItem(item.to_string()));
        }
        let (x, y, rotated) = self.find_spot(sizes, item).ok_or(PlaceError::NoRoom)?;
        let placed = Placed {
            uid,
            item: item.to_string(),
            x,
            y,
            rotated,
        };
        self.place(sizes, placed.clone())?;
        Ok(placed)
    }

    /// How many of `item` the grid holds.
    pub fn count(&self, item: &str) -> usize {
        self.items.iter().filter(|p| p.item == item).count()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sizes() -> Sizes {
        Sizes::from([
            ("scope".to_string(), Size { w: 3, h: 1 }),
            ("mag".to_string(), Size { w: 1, h: 2 }),
            ("box".to_string(), Size { w: 2, h: 2 }),
            ("cell".to_string(), Size { w: 1, h: 1 }),
        ])
    }

    fn at(uid: u32, item: &str, x: u8, y: u8, rotated: bool) -> Placed {
        Placed {
            uid,
            item: item.into(),
            x,
            y,
            rotated,
        }
    }

    #[test]
    fn an_item_fits_inside_the_grid_only() {
        let g = Grid::new(4, 3);
        assert!(g.check(&sizes(), "scope", 1, 0, false, None).is_ok());
        assert_eq!(
            g.check(&sizes(), "scope", 2, 0, false, None),
            Err(PlaceError::OutOfBounds)
        );
        assert_eq!(
            g.check(&sizes(), "scope", 0, 1, true, None),
            Err(PlaceError::OutOfBounds)
        );
    }

    #[test]
    fn items_may_not_overlap() {
        let mut g = Grid::new(4, 4);
        g.place(&sizes(), at(1, "box", 1, 1, false)).expect("free");
        assert_eq!(
            g.check(&sizes(), "mag", 2, 0, false, None),
            Err(PlaceError::Overlaps(1))
        );
        assert!(g.check(&sizes(), "mag", 3, 0, false, None).is_ok());
        assert!(g.check(&sizes(), "cell", 0, 0, false, None).is_ok());
    }

    #[test]
    fn turning_swaps_width_and_height() {
        let mut g = Grid::new(2, 3);
        assert!(g.place(&sizes(), at(1, "scope", 0, 0, false)).is_err());
        g.place(&sizes(), at(1, "scope", 0, 0, true))
            .expect("fits upright");
        assert!(g.check(&sizes(), "mag", 1, 0, false, None).is_ok());
    }

    #[test]
    fn moving_ignores_the_item_itself() {
        let mut g = Grid::new(4, 4);
        g.place(&sizes(), at(1, "box", 0, 0, false)).expect("free");
        g.move_to(&sizes(), 1, 1, 0, false)
            .expect("shifts over its old spot");
        assert_eq!(g.get(1).map(|p| p.x), Some(1));
    }

    #[test]
    fn a_failed_move_leaves_everything_where_it_was() {
        let mut g = Grid::new(4, 4);
        g.place(&sizes(), at(1, "box", 0, 0, false)).expect("free");
        g.place(&sizes(), at(2, "box", 2, 0, false)).expect("free");
        assert_eq!(
            g.move_to(&sizes(), 1, 1, 0, false),
            Err(PlaceError::Overlaps(2))
        );
        assert_eq!(g.get(1), Some(&at(1, "box", 0, 0, false)));
        assert_eq!(
            g.move_to(&sizes(), 9, 0, 0, false),
            Err(PlaceError::NoSuchUid(9))
        );
    }

    #[test]
    fn insert_finds_the_first_free_spot_turning_if_it_must() {
        let mut g = Grid::new(3, 3);
        g.place(&sizes(), at(1, "box", 0, 0, false)).expect("free");
        let mag = g.insert(&sizes(), 2, "mag").expect("room on the right");
        assert_eq!((mag.x, mag.y, mag.rotated), (2, 0, false));
        // Only the bottom row is left: a 1x2 magazine must lie down.
        let lying = g.insert(&sizes(), 3, "mag").expect("turns to fit");
        assert_eq!((lying.x, lying.y, lying.rotated), (0, 2, true));
        assert_eq!(g.insert(&sizes(), 4, "box"), Err(PlaceError::NoRoom));
    }

    #[test]
    fn uids_are_unique_and_items_known() {
        let mut g = Grid::new(4, 4);
        g.place(&sizes(), at(1, "cell", 0, 0, false)).expect("free");
        assert_eq!(
            g.place(&sizes(), at(1, "cell", 1, 0, false)),
            Err(PlaceError::DuplicateUid(1))
        );
        assert_eq!(
            g.insert(&sizes(), 2, "laser"),
            Err(PlaceError::UnknownItem("laser".into()))
        );
    }

    #[test]
    fn removing_frees_the_cells_and_counts_follow() {
        let mut g = Grid::new(2, 2);
        g.insert(&sizes(), 1, "box").expect("fits");
        assert_eq!(g.count("box"), 1);
        assert!(g.insert(&sizes(), 2, "cell").is_err());
        assert_eq!(g.remove(1).map(|p| p.uid), Some(1));
        assert_eq!(g.count("box"), 0);
        assert!(g.insert(&sizes(), 2, "cell").is_ok());
        assert_eq!(g.remove(1), None);
    }
}
