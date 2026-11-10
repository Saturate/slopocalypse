//! gdext binding for inventory_core: GDScript gets `InventoryGrid`, one grid of items.

// gdext's entry point must be an `unsafe impl` and its macro drops item-level allows, so
// binding crates allow unsafe at crate level. Pure crates keep it denied; keep logic there.
#![allow(unsafe_code)]

use godot::prelude::*;
mod gear;

use inventory_core::{Grid, Placed, Size, Sizes};

struct InventoryExtension;

#[gdextension]
unsafe impl ExtensionLibrary for InventoryExtension {}

/// GDScript: `var g := InventoryGrid.new(); g.setup(10, 6, {"item_id": [w, h], ...})`.
/// Changes return "" on success or why they were refused.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct InventoryGrid {
    grid: Option<Grid>,
    sizes: Sizes,
    base: Base<RefCounted>,
}

#[godot_api]
impl InventoryGrid {
    #[func]
    fn setup(&mut self, w: i64, h: i64, sizes: VarDictionary) {
        self.grid = Some(Grid::new(cell(w), cell(h)));
        self.sizes = sizes
            .iter_shared()
            .filter_map(|(id, size)| {
                let id = id.try_to::<GString>().ok()?.to_string();
                let a = size.try_to::<VarArray>().ok()?;
                let w = a.get(0)?.try_to::<f64>().ok()?;
                let h = a.get(1)?.try_to::<f64>().ok()?;
                Some((
                    id,
                    Size {
                        w: cell(w as i64),
                        h: cell(h as i64),
                    },
                ))
            })
            .collect();
    }

    #[func]
    fn width(&self) -> i64 {
        self.grid.as_ref().map_or(0, |g| i64::from(g.w))
    }

    #[func]
    fn height(&self) -> i64 {
        self.grid.as_ref().map_or(0, |g| i64::from(g.h))
    }

    /// Whether `item` fits at (x, y); `moving` is the uid being dragged, or -1.
    #[func]
    fn can_place(&self, item: GString, x: i64, y: i64, rotated: bool, moving: i64) -> bool {
        self.grid.as_ref().is_some_and(|g| {
            g.check(
                &self.sizes,
                &item.to_string(),
                cell(x),
                cell(y),
                rotated,
                u32::try_from(moving).ok(),
            )
            .is_ok()
        })
    }

    #[func]
    fn place(&mut self, uid: i64, item: GString, x: i64, y: i64, rotated: bool) -> GString {
        let Some(grid) = self.grid.as_mut() else {
            return "not set up".into();
        };
        let placed = Placed {
            uid: uid_of(uid),
            item: item.to_string(),
            x: cell(x),
            y: cell(y),
            rotated,
        };
        result(grid.place(&self.sizes, placed))
    }

    #[func]
    fn move_item(&mut self, uid: i64, x: i64, y: i64, rotated: bool) -> GString {
        let Some(grid) = self.grid.as_mut() else {
            return "not set up".into();
        };
        result(grid.move_to(&self.sizes, uid_of(uid), cell(x), cell(y), rotated))
    }

    /// Moves item `uid` from this grid to (x, y) in `to`; "" or why not. Within the same
    /// grid it is a plain move.
    #[func]
    fn transfer(
        &mut self,
        uid: i64,
        mut to: Gd<InventoryGrid>,
        x: i64,
        y: i64,
        rotated: bool,
    ) -> GString {
        if to == self.to_gd() {
            return self.move_item(uid, x, y, rotated);
        }
        let mut other = to.bind_mut();
        match (self.grid.as_mut(), other.grid.as_mut()) {
            (Some(from), Some(into)) => result(
                from.transfer(into, &self.sizes, uid_of(uid), cell(x), cell(y), rotated)
                    .map(|_| ()),
            ),
            _ => GString::from("not set up"),
        }
    }

    /// Moves item `uid` into the first free spot in `to`; "" or why not.
    #[func]
    fn transfer_anywhere(&mut self, uid: i64, mut to: Gd<InventoryGrid>) -> GString {
        if to == self.to_gd() {
            return GString::from("already here");
        }
        let mut other = to.bind_mut();
        match (self.grid.as_mut(), other.grid.as_mut()) {
            (Some(from), Some(into)) => result(
                from.transfer_anywhere(into, &self.sizes, uid_of(uid))
                    .map(|_| ()),
            ),
            _ => GString::from("not set up"),
        }
    }

    /// Puts `item` in the first free spot: `{ok, x, y, rotated, error}`.
    #[func]
    fn insert(&mut self, uid: i64, item: GString) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(grid) = self.grid.as_mut() else {
            out.set("ok", false);
            return out;
        };
        match grid.insert(&self.sizes, uid_of(uid), &item.to_string()) {
            Ok(p) => {
                out.set("ok", true);
                out.set("x", i64::from(p.x));
                out.set("y", i64::from(p.y));
                out.set("rotated", p.rotated);
            }
            Err(e) => {
                out.set("ok", false);
                out.set("error", e.to_string());
            }
        }
        out
    }

    #[func]
    fn remove(&mut self, uid: i64) -> bool {
        self.grid
            .as_mut()
            .is_some_and(|g| g.remove(uid_of(uid)).is_some())
    }

    #[func]
    fn count(&self, item: GString) -> i64 {
        self.grid.as_ref().map_or(0, |g| {
            i64::try_from(g.count(&item.to_string())).unwrap_or(i64::MAX)
        })
    }

    /// Every item as `{uid, item, x, y, rotated, w, h}` (w and h as placed).
    #[func]
    fn items(&self) -> VarArray {
        let mut out = VarArray::new();
        let Some(grid) = self.grid.as_ref() else {
            return out;
        };
        for p in grid.items() {
            let size = self
                .sizes
                .get(&p.item)
                .copied()
                .unwrap_or(Size { w: 1, h: 1 })
                .turned(p.rotated);
            let mut d = VarDictionary::new();
            d.set("uid", i64::from(p.uid));
            d.set("item", p.item.as_str());
            d.set("x", i64::from(p.x));
            d.set("y", i64::from(p.y));
            d.set("rotated", p.rotated);
            d.set("w", i64::from(size.w));
            d.set("h", i64::from(size.h));
            out.push(&d.to_variant());
        }
        out
    }
}

/// Grid coordinates are small; anything outside u8 lands out of bounds instead of wrapping.
pub(crate) fn cell(v: i64) -> u8 {
    u8::try_from(v.clamp(0, i64::from(u8::MAX))).unwrap_or(u8::MAX)
}

pub(crate) fn uid_of(v: i64) -> u32 {
    u32::try_from(v).unwrap_or(u32::MAX)
}

fn result(r: Result<(), inventory_core::PlaceError>) -> GString {
    match r {
        Ok(()) => GString::new(),
        Err(e) => GString::from(e.to_string().as_str()),
    }
}
