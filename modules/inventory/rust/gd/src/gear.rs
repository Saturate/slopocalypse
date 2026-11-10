//! `InventoryGear`: one owner's slots and grids (a player, a body, a crate) for GDScript.

use godot::prelude::*;
use inventory_core::gear::{Defs, Gear, GearError, ItemDef, Loc};
use inventory_core::{Placed, Size};

use crate::{cell, uid_of};

/// GDScript: `var g := InventoryGear.new(); g.setup(defs, layout)` where `defs` is
/// `{id: {size: [w, h], kind, grid: [w, h] (optional)}}` and `layout` is
/// `{slots: {name: kind}, fixed: {name: [w, h]}, fill_order: [names]}`. A place is
/// `{slot: name}` or `{grid: name, x, y, rotated}`. Changes return "" or why they were refused.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct InventoryGear {
    gear: Option<Gear>,
    defs: Defs,
    base: Base<RefCounted>,
}

#[godot_api]
impl InventoryGear {
    #[func]
    fn setup(&mut self, defs: VarDictionary, layout: VarDictionary) {
        self.defs = defs
            .iter_shared()
            .filter_map(|(id, def)| {
                let id = id.try_to::<GString>().ok()?.to_string();
                let d = def.try_to::<VarDictionary>().ok()?;
                let size = pair(&d.get("size")?)?;
                let kind = d
                    .get("kind")
                    .and_then(|k| k.try_to::<GString>().ok())
                    .map(|k| k.to_string())
                    .unwrap_or_default();
                let grid = d.get("grid").and_then(|g| pair(&g));
                Some((id, ItemDef { size, kind, grid }))
            })
            .collect();
        let slots: Vec<(String, String)> = dict(&layout, "slots")
            .iter_shared()
            .filter_map(|(n, k)| {
                Some((
                    n.try_to::<GString>().ok()?.to_string(),
                    k.try_to::<GString>().ok()?.to_string(),
                ))
            })
            .collect();
        let fixed: Vec<(String, Size)> = dict(&layout, "fixed")
            .iter_shared()
            .filter_map(|(n, s)| Some((n.try_to::<GString>().ok()?.to_string(), pair(&s)?)))
            .collect();
        let order: Vec<String> = layout
            .get("fill_order")
            .and_then(|o| o.try_to::<VarArray>().ok())
            .map(|a| {
                a.iter_shared()
                    .filter_map(|v| v.try_to::<GString>().ok())
                    .map(|s| s.to_string())
                    .collect()
            })
            .unwrap_or_default();
        let slot_refs: Vec<(&str, &str)> = slots
            .iter()
            .map(|(a, b)| (a.as_str(), b.as_str()))
            .collect();
        let fixed_refs: Vec<(&str, Size)> = fixed.iter().map(|(a, s)| (a.as_str(), *s)).collect();
        let order_refs: Vec<&str> = order.iter().map(String::as_str).collect();
        self.gear = Some(Gear::new(&slot_refs, &fixed_refs, &order_refs));
    }

    /// Every slot as `{name, kind, item}` (item `{uid, item}` or empty).
    #[func]
    fn slots(&self) -> VarArray {
        let mut out = VarArray::new();
        let Some(g) = self.gear.as_ref() else {
            return out;
        };
        for (name, kind) in g.slot_names() {
            let mut d = VarDictionary::new();
            d.set("name", name);
            d.set("kind", kind);
            let mut item = VarDictionary::new();
            if let Some(p) = g.slot_item(name) {
                item.set("uid", i64::from(p.uid));
                item.set("item", p.item.as_str());
            }
            d.set("item", &item);
            out.push(&d.to_variant());
        }
        out
    }

    /// Open grids: fixed ones first, then those opened by worn items.
    #[func]
    fn grid_names(&self) -> PackedStringArray {
        let mut out = PackedStringArray::new();
        if let Some(g) = self.gear.as_ref() {
            for n in g.grid_names() {
                out.push(n.as_str());
            }
        }
        out
    }

    #[func]
    fn grid_size(&self, name: GString) -> Vector2i {
        self.gear
            .as_ref()
            .and_then(|g| g.grid(&name.to_string()))
            .map_or(Vector2i::ZERO, |grid| {
                Vector2i::new(i32::from(grid.w), i32::from(grid.h))
            })
    }

    /// Items in one grid as `{uid, item, x, y, rotated, w, h}` (w and h as placed).
    #[func]
    fn items(&self, name: GString) -> VarArray {
        let mut out = VarArray::new();
        if let Some(grid) = self.gear.as_ref().and_then(|g| g.grid(&name.to_string())) {
            for p in grid.items() {
                out.push(&self.placed(p).to_variant());
            }
        }
        out
    }

    /// Every item anywhere as `{uid, item, slot}` or `{uid, item, grid, x, y, rotated, w, h}`.
    #[func]
    fn all_items(&self) -> VarArray {
        let mut out = VarArray::new();
        let Some(g) = self.gear.as_ref() else {
            return out;
        };
        for (loc, p) in g.all() {
            let mut d = self.placed(p);
            match loc {
                Loc::Slot(name) => d.set("slot", name.as_str()),
                Loc::Grid { name, .. } => d.set("grid", name.as_str()),
            }
            out.push(&d.to_variant());
        }
        out
    }

    /// Whether `item` (with things inside if `full`) may go to `place`; `moving` is its uid
    /// when it is already in this gear, else -1.
    #[func]
    fn can_place(&self, item: GString, full: bool, place: VarDictionary, moving: i64) -> bool {
        let (Some(g), Some(loc)) = (self.gear.as_ref(), loc_of(&place)) else {
            return false;
        };
        let moving = (moving >= 0).then(|| uid_of(moving));
        g.check(&self.defs, &item.to_string(), full, &loc, moving)
            .is_ok()
    }

    /// Whether `uid` is a worn rig or backpack with something in it.
    #[func]
    fn is_full(&self, uid: i64) -> bool {
        let Some(g) = self.gear.as_ref() else {
            return false;
        };
        matches!(g.find(uid_of(uid)), Some(Loc::Slot(name)) if g.grid(&name).is_some_and(|grid| !grid.items().is_empty()))
    }

    #[func]
    fn move_item(&mut self, uid: i64, place: VarDictionary) -> GString {
        let Some(loc) = loc_of(&place) else {
            return GString::from("no such place");
        };
        let defs = &self.defs;
        match self.gear.as_mut() {
            Some(g) => result(g.move_to(defs, uid_of(uid), &loc)),
            None => GString::from("not set up"),
        }
    }

    /// Moves `uid` to `place` in `to`; within the same gear it is a plain move.
    #[func]
    fn transfer(&mut self, uid: i64, mut to: Gd<InventoryGear>, place: VarDictionary) -> GString {
        if to == self.to_gd() {
            return self.move_item(uid, place);
        }
        let Some(loc) = loc_of(&place) else {
            return GString::from("no such place");
        };
        let mut other = to.bind_mut();
        let defs = &self.defs;
        match (self.gear.as_mut(), other.gear.as_mut()) {
            (Some(from), Some(into)) => result(from.transfer(into, defs, uid_of(uid), &loc)),
            _ => GString::from("not set up"),
        }
    }

    /// Moves `uid` into the first place it fits in `to` (an empty slot of its kind first).
    #[func]
    fn transfer_anywhere(&mut self, uid: i64, mut to: Gd<InventoryGear>) -> GString {
        if to == self.to_gd() {
            return GString::from("already here");
        }
        let mut other = to.bind_mut();
        let defs = &self.defs;
        match (self.gear.as_mut(), other.gear.as_mut()) {
            (Some(from), Some(into)) => result(from.transfer_anywhere(into, defs, uid_of(uid))),
            _ => GString::from("not set up"),
        }
    }

    /// Puts a new item in the first place it fits: `{ok, error}`.
    #[func]
    fn insert(&mut self, uid: i64, item: GString) -> VarDictionary {
        let mut out = VarDictionary::new();
        let defs = &self.defs;
        let r = self
            .gear
            .as_mut()
            .map(|g| g.insert(defs, uid_of(uid), &item.to_string()));
        match r {
            Some(Ok(_)) => out.set("ok", true),
            Some(Err(e)) => {
                out.set("ok", false);
                out.set("error", e.to_string());
            }
            None => out.set("ok", false),
        }
        out
    }

    /// Puts a new item at `place`; "" or why not.
    #[func]
    fn place(&mut self, uid: i64, item: GString, place: VarDictionary) -> GString {
        let Some(loc) = loc_of(&place) else {
            return GString::from("no such place");
        };
        let defs = &self.defs;
        let Some(g) = self.gear.as_mut() else {
            return GString::from("not set up");
        };
        if g.find(uid_of(uid)).is_some() {
            return GString::from("already here");
        }
        let lifted = inventory_core::gear::Lifted {
            placed: Placed {
                uid: uid_of(uid),
                item: item.to_string(),
                x: 0,
                y: 0,
                rotated: false,
            },
            contents: None,
        };
        result(g.put(defs, lifted, &loc))
    }

    /// Takes an item out for good; "" or why not (a worn bag with things in it stays).
    #[func]
    fn remove(&mut self, uid: i64) -> GString {
        match self.gear.as_mut() {
            Some(g) => result(g.remove(uid_of(uid)).map(|_| ())),
            None => GString::from("not set up"),
        }
    }

    #[func]
    fn count(&self, item: GString) -> i64 {
        self.gear.as_ref().map_or(0, |g| {
            i64::try_from(g.count(&item.to_string())).unwrap_or(i64::MAX)
        })
    }

    #[func]
    fn is_empty(&self) -> bool {
        self.gear.as_ref().is_none_or(Gear::is_empty)
    }

    /// The whole gear as `{slots: {name: {uid, item}}, grids: {name: [{uid, item, x, y,
    /// rotated}]}}`, for sending and saving.
    #[func]
    fn snapshot(&self) -> VarDictionary {
        let mut slots = VarDictionary::new();
        let mut grids = VarDictionary::new();
        if let Some(g) = self.gear.as_ref() {
            for (name, _) in g.slot_names() {
                if let Some(p) = g.slot_item(name) {
                    let mut d = VarDictionary::new();
                    d.set("uid", i64::from(p.uid));
                    d.set("item", p.item.as_str());
                    slots.set(name, &d);
                }
            }
            for name in g.grid_names() {
                let mut a = VarArray::new();
                for p in g.grid(&name).map(|x| x.items()).unwrap_or_default() {
                    a.push(&self.placed(p).to_variant());
                }
                grids.set(name.as_str(), &a);
            }
        }
        let mut out = VarDictionary::new();
        out.set("slots", &slots);
        out.set("grids", &grids);
        out
    }

    fn placed(&self, p: &Placed) -> VarDictionary {
        let size = self
            .defs
            .get(&p.item)
            .map_or(Size { w: 1, h: 1 }, |d| d.size)
            .turned(p.rotated);
        let mut d = VarDictionary::new();
        d.set("uid", i64::from(p.uid));
        d.set("item", p.item.as_str());
        d.set("x", i64::from(p.x));
        d.set("y", i64::from(p.y));
        d.set("rotated", p.rotated);
        d.set("w", i64::from(size.w));
        d.set("h", i64::from(size.h));
        d
    }
}

fn dict(d: &VarDictionary, key: &str) -> VarDictionary {
    d.get(key)
        .and_then(|v| v.try_to::<VarDictionary>().ok())
        .unwrap_or_default()
}

fn pair(v: &Variant) -> Option<Size> {
    let a = v.try_to::<VarArray>().ok()?;
    let w = a.get(0)?.try_to::<f64>().ok()?;
    let h = a.get(1)?.try_to::<f64>().ok()?;
    Some(Size {
        w: cell(w as i64),
        h: cell(h as i64),
    })
}

fn loc_of(place: &VarDictionary) -> Option<Loc> {
    if let Some(slot) = place.get("slot").and_then(|s| s.try_to::<GString>().ok()) {
        return Some(Loc::Slot(slot.to_string()));
    }
    let name = place.get("grid")?.try_to::<GString>().ok()?.to_string();
    let num = |k: &str| {
        place
            .get(k)
            .and_then(|v| v.try_to::<i64>().ok())
            .unwrap_or(0)
    };
    Some(Loc::Grid {
        name,
        x: cell(num("x")),
        y: cell(num("y")),
        rotated: place
            .get("rotated")
            .and_then(|v| v.try_to::<bool>().ok())
            .unwrap_or(false),
    })
}

fn result(r: Result<(), GearError>) -> GString {
    match r {
        Ok(()) => GString::new(),
        Err(e) => GString::from(e.to_string().as_str()),
    }
}
