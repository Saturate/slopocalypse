//! Everything one owner carries: equipment slots that each take one item of their kind,
//! and named grids (pockets, plus the grid a worn rig or backpack opens). A crate is the
//! same thing with one grid and no slots, so bodies, players and crates all move items the
//! same way.
//!
//! Rules beyond the grid rules: a slot takes one item of its kind; wearing an item that has a
//! grid (a rig, a backpack) opens that grid under the slot's name, and taking it off closes
//! it. A worn item with things inside may only move to another slot, its contents with it;
//! anywhere else it must be emptied first.

use std::collections::BTreeMap;

use crate::{Grid, PlaceError, Placed, Size, Sizes};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ItemDef {
    pub size: Size,
    pub kind: String,
    /// The grid this item opens when worn in a slot.
    pub grid: Option<Size>,
}

pub type Defs = BTreeMap<String, ItemDef>;

/// Where an item is, or is going.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Loc {
    Slot(String),
    Grid {
        name: String,
        x: u8,
        y: u8,
        rotated: bool,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GearError {
    Place(PlaceError),
    NoSuchSlot(String),
    NoSuchGrid(String),
    SlotTaken(String),
    WrongKind { slot: String, kind: String },
    NotEmpty,
    IntoItself,
}

impl From<PlaceError> for GearError {
    fn from(e: PlaceError) -> Self {
        GearError::Place(e)
    }
}

impl std::fmt::Display for GearError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Place(e) => e.fmt(f),
            Self::NoSuchSlot(s) => write!(f, "no '{s}' slot"),
            Self::NoSuchGrid(g) => write!(f, "no '{g}' to put it in"),
            Self::SlotTaken(s) => write!(f, "the {s} slot is taken"),
            Self::WrongKind { slot, kind } => write!(f, "a {kind} does not go in the {slot} slot"),
            Self::NotEmpty => write!(f, "empty it first"),
            Self::IntoItself => write!(f, "it cannot go inside itself"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Slot {
    kind: String,
    item: Option<Placed>,
}

/// An item lifted out of a gear: the item and, for a worn rig or backpack, what was in it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Lifted {
    pub placed: Placed,
    pub contents: Option<Grid>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Gear {
    slots: BTreeMap<String, Slot>,
    grids: BTreeMap<String, Grid>,
    /// Grids that are always there (pockets, a crate's grid), as opposed to opened by a slot.
    fixed: Vec<String>,
    /// Where a picked-up item goes first: grid names in order.
    fill_order: Vec<String>,
}

pub fn sizes_of(defs: &Defs) -> Sizes {
    defs.iter().map(|(id, d)| (id.clone(), d.size)).collect()
}

impl Gear {
    /// `slots` is slot name -> the kind it takes; `fixed` are grids always there.
    pub fn new(slots: &[(&str, &str)], fixed: &[(&str, Size)], fill_order: &[&str]) -> Self {
        Self {
            slots: slots
                .iter()
                .map(|(name, kind)| {
                    (
                        (*name).to_string(),
                        Slot {
                            kind: (*kind).to_string(),
                            item: None,
                        },
                    )
                })
                .collect(),
            grids: fixed
                .iter()
                .map(|(name, size)| ((*name).to_string(), Grid::new(size.w, size.h)))
                .collect(),
            fixed: fixed.iter().map(|(n, _)| (*n).to_string()).collect(),
            fill_order: fill_order.iter().map(|s| (*s).to_string()).collect(),
        }
    }

    pub fn slot_names(&self) -> impl Iterator<Item = (&str, &str)> {
        self.slots
            .iter()
            .map(|(n, s)| (n.as_str(), s.kind.as_str()))
    }

    pub fn slot_item(&self, slot: &str) -> Option<&Placed> {
        self.slots.get(slot)?.item.as_ref()
    }

    pub fn grid(&self, name: &str) -> Option<&Grid> {
        self.grids.get(name)
    }

    /// Open grids in display order: fixed ones first, then those opened by slots in fill
    /// order, then any others.
    pub fn grid_names(&self) -> Vec<String> {
        let mut out = self.fixed.clone();
        for name in self.fill_order.iter().chain(self.slots.keys()) {
            if self.grids.contains_key(name) && !out.contains(name) {
                out.push(name.clone());
            }
        }
        out
    }

    pub fn is_empty(&self) -> bool {
        self.slots.values().all(|s| s.item.is_none())
            && self.grids.values().all(|g| g.items().is_empty())
    }

    /// Every item, wherever it is, with where.
    pub fn all(&self) -> Vec<(Loc, &Placed)> {
        let mut out = Vec::new();
        for (name, slot) in &self.slots {
            if let Some(p) = &slot.item {
                out.push((Loc::Slot(name.clone()), p));
            }
        }
        for (name, grid) in &self.grids {
            for p in grid.items() {
                out.push((
                    Loc::Grid {
                        name: name.clone(),
                        x: p.x,
                        y: p.y,
                        rotated: p.rotated,
                    },
                    p,
                ));
            }
        }
        out
    }

    pub fn find(&self, uid: u32) -> Option<Loc> {
        self.all()
            .into_iter()
            .find(|(_, p)| p.uid == uid)
            .map(|(l, _)| l)
    }

    pub fn count(&self, item: &str) -> usize {
        self.all().iter().filter(|(_, p)| p.item == item).count()
    }

    /// Whether `item` (carrying things inside if `full`) may go to `to`. `moving` is the
    /// uid of the item itself, ignored for overlap when it moves within one grid.
    pub fn check(
        &self,
        defs: &Defs,
        item: &str,
        full: bool,
        to: &Loc,
        moving: Option<u32>,
    ) -> Result<(), GearError> {
        let def = defs
            .get(item)
            .ok_or_else(|| PlaceError::UnknownItem(item.to_string()))?;
        match to {
            Loc::Slot(name) => {
                let slot = self
                    .slots
                    .get(name)
                    .ok_or_else(|| GearError::NoSuchSlot(name.clone()))?;
                if slot.kind != def.kind {
                    return Err(GearError::WrongKind {
                        slot: name.clone(),
                        kind: def.kind.clone(),
                    });
                }
                match &slot.item {
                    Some(p) if Some(p.uid) != moving => Err(GearError::SlotTaken(name.clone())),
                    _ => Ok(()),
                }
            }
            Loc::Grid {
                name,
                x,
                y,
                rotated,
            } => {
                if full {
                    return Err(GearError::NotEmpty);
                }
                // A worn bag cannot go into the grid it opens.
                if let Some(m) = moving
                    && self.slot_item(name).is_some_and(|p| p.uid == m)
                {
                    return Err(GearError::IntoItself);
                }
                let grid = self
                    .grids
                    .get(name)
                    .ok_or_else(|| GearError::NoSuchGrid(name.clone()))?;
                let sizes = sizes_of(defs);
                let skip = moving.filter(|m| grid.get(*m).is_some());
                grid.check(&sizes, item, *x, *y, *rotated, skip)?;
                Ok(())
            }
        }
    }

    /// Lifts an item out, closing the grid of a worn rig or backpack (its contents come too).
    pub fn lift(&mut self, uid: u32) -> Result<Lifted, GearError> {
        match self.find(uid).ok_or(PlaceError::NoSuchUid(uid))? {
            Loc::Slot(name) => {
                let placed = self
                    .slots
                    .get_mut(&name)
                    .and_then(|s| s.item.take())
                    .ok_or(PlaceError::NoSuchUid(uid))?;
                let contents = self.grids.remove(&name);
                Ok(Lifted { placed, contents })
            }
            Loc::Grid { name, .. } => {
                let placed = self
                    .grids
                    .get_mut(&name)
                    .and_then(|g| g.remove(uid))
                    .ok_or(PlaceError::NoSuchUid(uid))?;
                Ok(Lifted {
                    placed,
                    contents: None,
                })
            }
        }
    }

    /// Puts a lifted item at `to`, opening its grid if it goes in a slot.
    pub fn put(&mut self, defs: &Defs, lifted: Lifted, to: &Loc) -> Result<(), GearError> {
        let full = lifted
            .contents
            .as_ref()
            .is_some_and(|g| !g.items().is_empty());
        self.check(defs, &lifted.placed.item, full, to, None)?;
        let Lifted {
            mut placed,
            contents,
        } = lifted;
        match to {
            Loc::Slot(name) => {
                let opens = defs.get(&placed.item).and_then(|d| d.grid);
                placed.x = 0;
                placed.y = 0;
                placed.rotated = false;
                if let Some(slot) = self.slots.get_mut(name) {
                    slot.item = Some(placed);
                }
                if let Some(size) = opens {
                    let grid = contents.unwrap_or_else(|| Grid::new(size.w, size.h));
                    self.grids.insert(name.clone(), grid);
                }
            }
            Loc::Grid {
                name,
                x,
                y,
                rotated,
            } => {
                placed.x = *x;
                placed.y = *y;
                placed.rotated = *rotated;
                let sizes = sizes_of(defs);
                if let Some(grid) = self.grids.get_mut(name) {
                    grid.place(&sizes, placed)?;
                }
            }
        }
        Ok(())
    }

    /// Moves an item within this gear. Nothing changes if it is refused.
    pub fn move_to(&mut self, defs: &Defs, uid: u32, to: &Loc) -> Result<(), GearError> {
        let from = self.find(uid).ok_or(PlaceError::NoSuchUid(uid))?;
        if let Loc::Grid { name, .. } = to
            && from == Loc::Slot(name.clone())
        {
            return Err(GearError::IntoItself);
        }
        let lifted = self.lift(uid)?;
        let backup = lifted.clone();
        if let Err(e) = self.put(defs, lifted, to) {
            self.restore(defs, backup, &from);
            return Err(e);
        }
        Ok(())
    }

    /// Moves an item from this gear to `to` in another one. Nothing changes if refused.
    pub fn transfer(
        &mut self,
        other: &mut Gear,
        defs: &Defs,
        uid: u32,
        to: &Loc,
    ) -> Result<(), GearError> {
        let from = self.find(uid).ok_or(PlaceError::NoSuchUid(uid))?;
        if other.find(uid).is_some() {
            return Err(PlaceError::DuplicateUid(uid).into());
        }
        let lifted = self.lift(uid)?;
        let backup = lifted.clone();
        if let Err(e) = other.put(defs, lifted, to) {
            self.restore(defs, backup, &from);
            return Err(e);
        }
        Ok(())
    }

    /// Where `item` would go first in this gear: an empty slot of its kind, else the first
    /// free spot in the grids in fill order.
    pub fn spot_for(&self, defs: &Defs, item: &str, full: bool) -> Option<Loc> {
        let def = defs.get(item)?;
        for (name, slot) in &self.slots {
            if slot.kind == def.kind && slot.item.is_none() {
                return Some(Loc::Slot(name.clone()));
            }
        }
        if full {
            return None;
        }
        let sizes = sizes_of(defs);
        for name in self.fill_names() {
            if let Some((x, y, rotated)) = self.grids.get(&name)?.find_spot(&sizes, item) {
                return Some(Loc::Grid {
                    name,
                    x,
                    y,
                    rotated,
                });
            }
        }
        None
    }

    /// Moves an item from this gear into the first place it fits in `other`.
    pub fn transfer_anywhere(
        &mut self,
        other: &mut Gear,
        defs: &Defs,
        uid: u32,
    ) -> Result<(), GearError> {
        let (_, placed) = self
            .all()
            .into_iter()
            .find(|(_, p)| p.uid == uid)
            .ok_or(PlaceError::NoSuchUid(uid))?;
        let item = placed.item.clone();
        let full = matches!(self.find(uid), Some(Loc::Slot(ref s)) if self.grids.get(s).is_some_and(|g| !g.items().is_empty()));
        let to = other.spot_for(defs, &item, full).ok_or(if full {
            GearError::NotEmpty
        } else {
            PlaceError::NoRoom.into()
        })?;
        self.transfer(other, defs, uid, &to)
    }

    /// Puts a new item in the first place it fits, as picking something up does.
    pub fn insert(&mut self, defs: &Defs, uid: u32, item: &str) -> Result<Loc, GearError> {
        if self.find(uid).is_some() {
            return Err(PlaceError::DuplicateUid(uid).into());
        }
        let to = self.spot_for(defs, item, false).ok_or(PlaceError::NoRoom)?;
        let placed = Placed {
            uid,
            item: item.to_string(),
            x: 0,
            y: 0,
            rotated: false,
        };
        self.put(
            defs,
            Lifted {
                placed,
                contents: None,
            },
            &to,
        )?;
        Ok(to)
    }

    /// Takes an item out for good (used, dropped). A worn rig or backpack with things in it
    /// stays: it must be emptied first.
    pub fn remove(&mut self, uid: u32) -> Result<Placed, GearError> {
        if let Some(Loc::Slot(name)) = self.find(uid)
            && self.grids.get(&name).is_some_and(|g| !g.items().is_empty())
        {
            return Err(GearError::NotEmpty);
        }
        Ok(self.lift(uid)?.placed)
    }

    fn fill_names(&self) -> Vec<String> {
        let mut names: Vec<String> = self
            .fill_order
            .iter()
            .filter(|n| self.grids.contains_key(*n))
            .cloned()
            .collect();
        for n in self.grid_names() {
            if !names.contains(&n) {
                names.push(n);
            }
        }
        names
    }

    fn restore(&mut self, defs: &Defs, lifted: Lifted, from: &Loc) {
        // The spot was just freed, so this cannot fail; if it somehow does, keep the item
        // anywhere rather than lose it.
        if self.put(defs, lifted.clone(), from).is_err()
            && let Some(to) = self.spot_for(defs, &lifted.placed.item, false)
        {
            let _ = self.put(defs, lifted, &to);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn defs() -> Defs {
        let d = |w, h, kind: &str, grid: Option<(u8, u8)>| ItemDef {
            size: Size { w, h },
            kind: kind.into(),
            grid: grid.map(|(w, h)| Size { w, h }),
        };
        Defs::from([
            ("cell".into(), d(1, 1, "part", None)),
            ("long".into(), d(3, 1, "part", None)),
            ("rig".into(), d(2, 2, "rig", Some((3, 2)))),
            ("bag".into(), d(3, 3, "backpack", Some((4, 4)))),
            ("bag2".into(), d(3, 3, "backpack", Some((2, 2)))),
        ])
    }

    fn player() -> Gear {
        Gear::new(
            &[("rig", "rig"), ("backpack", "backpack")],
            &[("pockets", Size { w: 4, h: 1 })],
            &["rig", "pockets", "backpack"],
        )
    }

    fn crate_gear() -> Gear {
        Gear::new(&[], &[("crate", Size { w: 6, h: 4 })], &["crate"])
    }

    fn at(name: &str, x: u8, y: u8) -> Loc {
        Loc::Grid {
            name: name.into(),
            x,
            y,
            rotated: false,
        }
    }

    #[test]
    fn a_slot_takes_only_its_kind() {
        let mut g = player();
        g.insert(&defs(), 1, "cell").expect("pocket");
        assert_eq!(
            g.move_to(&defs(), 1, &Loc::Slot("rig".into())),
            Err(GearError::WrongKind {
                slot: "rig".into(),
                kind: "part".into()
            })
        );
        assert_eq!(g.find(1), Some(at("pockets", 0, 0)));
    }

    #[test]
    fn wearing_a_bag_opens_its_grid_and_taking_it_off_closes_it() {
        let mut g = player();
        assert!(g.grid("backpack").is_none());
        assert_eq!(
            g.insert(&defs(), 1, "bag"),
            Ok(Loc::Slot("backpack".into()))
        );
        assert_eq!(g.grid("backpack").map(|b| (b.w, b.h)), Some((4, 4)));
        let mut c = crate_gear();
        g.transfer(&mut c, &defs(), 1, &at("crate", 0, 0))
            .expect("an empty bag goes in the crate");
        assert!(g.grid("backpack").is_none());
    }

    #[test]
    fn picked_up_items_fill_the_rig_then_pockets_then_backpack() {
        let mut g = player();
        g.insert(&defs(), 1, "rig").expect("worn");
        g.insert(&defs(), 2, "bag").expect("worn");
        for uid in 10..16 {
            assert!(
                matches!(g.insert(&defs(), uid, "cell"), Ok(Loc::Grid { ref name, .. }) if name == "rig")
            );
        }
        assert!(
            matches!(g.insert(&defs(), 20, "cell"), Ok(Loc::Grid { ref name, .. }) if name == "pockets")
        );
        // A long part fits neither the full rig nor the pockets now holding one.
        assert!(
            matches!(g.insert(&defs(), 21, "long"), Ok(Loc::Grid { ref name, .. }) if name == "pockets")
        );
        assert!(
            matches!(g.insert(&defs(), 22, "long"), Ok(Loc::Grid { ref name, .. }) if name == "backpack")
        );
    }

    #[test]
    fn a_full_bag_moves_between_slots_with_its_contents_only() {
        let mut body = player();
        body.insert(&defs(), 1, "bag").expect("worn");
        body.insert(&defs(), 2, "long").expect("pockets");
        body.move_to(&defs(), 2, &at("backpack", 0, 0))
            .expect("into the bag");
        let mut me = player();
        me.insert(&defs(), 3, "cell").expect("pocket");
        let mut c = crate_gear();
        assert_eq!(
            body.transfer(&mut c, &defs(), 1, &at("crate", 0, 0)),
            Err(GearError::NotEmpty)
        );
        assert!(body.find(2).is_some());
        body.transfer(&mut me, &defs(), 1, &Loc::Slot("backpack".into()))
            .expect("slot to slot");
        assert!(body.grid("backpack").is_none());
        assert_eq!(me.grid("backpack").map(|b| b.items().len()), Some(1));
        assert_eq!(me.count("long"), 1);
    }

    #[test]
    fn a_taken_slot_refuses_and_nothing_moves() {
        let mut body = player();
        body.insert(&defs(), 1, "bag").expect("worn");
        let mut me = player();
        me.insert(&defs(), 2, "bag2").expect("worn");
        assert_eq!(
            body.transfer(&mut me, &defs(), 1, &Loc::Slot("backpack".into())),
            Err(GearError::SlotTaken("backpack".into()))
        );
        assert!(body.grid("backpack").is_some());
        assert_eq!(me.grid("backpack").map(|b| b.w), Some(2));
    }

    #[test]
    fn a_worn_bag_cannot_go_inside_itself() {
        let mut g = player();
        g.insert(&defs(), 1, "bag").expect("worn");
        assert_eq!(
            g.move_to(&defs(), 1, &at("backpack", 0, 0)),
            Err(GearError::IntoItself)
        );
        assert_eq!(g.find(1), Some(Loc::Slot("backpack".into())));
    }

    #[test]
    fn moves_within_a_grid_ignore_the_item_itself_and_failures_restore() {
        let mut g = player();
        g.insert(&defs(), 1, "long").expect("pockets");
        g.move_to(&defs(), 1, &at("pockets", 1, 0))
            .expect("shift right");
        assert_eq!(g.find(1), Some(at("pockets", 1, 0)));
        assert!(g.move_to(&defs(), 1, &at("pockets", 2, 0)).is_err());
        assert_eq!(g.find(1), Some(at("pockets", 1, 0)));
        assert_eq!(
            g.move_to(&defs(), 1, &at("backpack", 0, 0)),
            Err(GearError::NoSuchGrid("backpack".into()))
        );
        assert_eq!(g.find(1), Some(at("pockets", 1, 0)));
    }

    #[test]
    fn transfer_anywhere_prefers_an_empty_slot() {
        let mut c = crate_gear();
        c.insert(&defs(), 1, "rig").expect("in the crate");
        let mut me = player();
        c.transfer_anywhere(&mut me, &defs(), 1).expect("worn");
        assert_eq!(me.find(1), Some(Loc::Slot("rig".into())));
        assert!(me.grid("rig").is_some());
        assert!(c.is_empty());
    }

    #[test]
    fn removing_a_full_bag_is_refused() {
        let mut g = player();
        g.insert(&defs(), 1, "bag").expect("worn");
        g.insert(&defs(), 2, "long").expect("pockets");
        g.move_to(&defs(), 2, &at("backpack", 0, 0))
            .expect("into the bag");
        assert_eq!(g.remove(1), Err(GearError::NotEmpty));
        assert_eq!(g.remove(2).map(|p| p.uid), Ok(2));
        assert_eq!(g.remove(1).map(|p| p.uid), Ok(1));
    }
}
